import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as parser;
import 'package:novelty/providers/site_rate_limiter_provider.dart';
import 'package:novelty/repositories/auth_repository.dart';
import 'package:novelty/services/http_client.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:novelty/utils/request_rate_limiter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
part 'narou_auth_service.g.dart';

const _loginUrl = 'https://syosetu.com/login/login/';
const _loginInputUrl = 'https://syosetu.com/login/input/';
const _bookmarkListUrl = 'https://syosetu.com/favnovelmain/list/';
const _cookieMonths = <String, int>{
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'apr': 4,
  'may': 5,
  'jun': 6,
  'jul': 7,
  'aug': 8,
  'sep': 9,
  'oct': 10,
  'nov': 11,
  'dec': 12,
};

/// なろうへのHTTPリクエストで使用するUser-Agent。
const narouUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
    'AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/126.0.0.0 Safari/537.36';

@Riverpod(keepAlive: true)
/// なろう認証サービスのプロバイダー。
NarouAuthService narouAuthService(Ref ref) {
  return NarouAuthService(
    authRepository: ref.watch(authRepositoryProvider),
    rateLimiter: ref.watch(siteRateLimiterProvider(NovelSource.narou)),
  );
}

/// なろうへのログイン・セッション管理を行うサービス。
///
/// セキュリティ設計：
/// - 認証Cookie (`ks2`, `ses`, `userl`) は`AuthRepository`経由でKeyChain/Keystoreに保存する。
/// - 認証Cookieはなろう (`syosetu.com`) へのリクエストにのみ付与する。
/// - 小説API (`api.syosetu.com`)、小説本文取得、検索では認証Cookieを使用しない。
class NarouAuthService {
  /// コンストラクタ。
  NarouAuthService({
    required this.authRepository,
    Dio? dio,
    RequestRateLimiter? rateLimiter,
  }) : _dio =
           dio ??
           createNoveltyDio(
             rateLimiter: rateLimiter,
           );

  /// 認証情報リポジトリ。
  final AuthRepository authRepository;

  /// HTTPクライアント。レート制限とタイムアウトは共通ファクトリで設定する。
  final Dio _dio;
  _PendingNarouMfa? _pendingMfa;
  int _authOperationGeneration = 0;
  Future<void> _sessionMutationQueue = Future<void>.value();

  /// ログインPOSTリクエストを送信し、セッションCookieを取得・保存する。
  ///
  /// 成功した場合は`NarouLoginResult.success`を返す。
  /// 失敗した場合はエラーメッセージを含む`NarouLoginResult.failure`を返す。
  Future<NarouLoginResult> login({
    required String narouid,
    required String password,
  }) async {
    cancelMfaChallenge();
    final generation = _authOperationGeneration;
    try {
      final formResponse = await _dio.get<String>(
        _loginInputUrl,
        options: _htmlOptions(),
      );
      if (!_isCurrentAuthOperation(generation)) return _cancelledLoginResult;
      final loginForm = _findForm(parser.parse(formResponse.data ?? ''), [
        'narouid',
        'pass',
      ]);
      if (loginForm == null) {
        return const NarouLoginResult.failure('ログイン画面の認証情報を取得できませんでした');
      }

      final cookies = <String, String>{};
      _mergeCookies(cookies, formResponse.headers.map['set-cookie']);
      final loginFields = _hiddenFields(loginForm)
        ..['narouid'] = narouid
        ..['pass'] = password;
      final loginAction = _formAction(
        loginForm,
        formResponse.realUri,
        fallback: Uri.parse(_loginUrl),
      );
      if (!_isNarouLoginAction(loginAction)) {
        return const NarouLoginResult.failure('ログイン先を安全に確認できませんでした');
      }

      final response = await _dio.post<String>(
        loginAction.toString(),
        data: loginFields,
        options: _htmlOptions(
          headers: {
            'Referer': _loginInputUrl,
            ...?_cookieHeaderMap(cookies),
          },
        ),
      );
      if (!_isCurrentAuthOperation(generation)) return _cancelledLoginResult;
      _mergeCookies(cookies, response.headers.map['set-cookie']);
      var challengeUri = _responseRedirect(response);
      Response<String>? challengeResponse;
      for (
        var redirects = 0;
        challengeUri != null && redirects < 5;
        redirects++
      ) {
        if (!_isNarouUri(challengeUri)) {
          return const NarouLoginResult.failure('認証先を安全に確認できませんでした');
        }
        challengeResponse = await _dio.get<String>(
          challengeUri.toString(),
          options: _htmlOptions(
            headers: {
              ...?_cookieHeaderMap(cookies),
            },
          ),
        );
        if (!_isCurrentAuthOperation(generation)) {
          return _cancelledLoginResult;
        }
        _mergeCookies(cookies, challengeResponse.headers.map['set-cookie']);
        challengeUri = _responseRedirect(challengeResponse);
      }
      if (challengeUri != null) {
        return const NarouLoginResult.failure('認証画面への転送回数が上限を超えました');
      }

      final challengePage = challengeResponse?.data ?? response.data ?? '';
      final pageUri = challengeResponse?.realUri ?? response.realUri;
      final pending = _parseMfaChallenge(
        challengePage,
        pageUri,
        cookies,
        narouid,
      );
      if (!_isCurrentAuthOperation(generation)) return _cancelledLoginResult;
      if (pending == null) {
        return const NarouLoginResult.failure(
          'ログインに失敗しました。ID・パスワードと二段階認証の表示を確認してください。',
        );
      }
      _pendingMfa = pending;
      return const NarouLoginResult.mfaRequired();
    } on DioException catch (e) {
      if (!_isCurrentAuthOperation(generation)) return _cancelledLoginResult;
      debugPrint(
        '[NarouAuth] login: 通信失敗 '
        'type=${e.type} status=${e.response?.statusCode}',
      );
      return const NarouLoginResult.failure('ログイン通信に失敗しました');
    } on Object catch (e) {
      if (!_isCurrentAuthOperation(generation)) return _cancelledLoginResult;
      debugPrint('[NarouAuth] login: 処理失敗 type=${e.runtimeType}');
      return const NarouLoginResult.failure('ログイン処理に失敗しました');
    }
  }

  /// メールまたは認証アプリで受け取った確認コードを一度だけ送信する。
  Future<NarouLoginResult> verifyMfaCode(String code) async {
    final pending = _pendingMfa;
    final generation = _authOperationGeneration;
    if (pending == null) {
      return const NarouLoginResult.failure('認証コードを確認できません。最初からログインしてください。');
    }
    final normalizedCode = code.trim();
    if (!RegExp(r'^\d{1,32}$').hasMatch(normalizedCode)) {
      return const NarouLoginResult.failure('認証コードを半角数字で入力してください。');
    }

    try {
      final fields = Map<String, String>.of(pending.hiddenFields)
        ..[pending.codeField] = normalizedCode;
      var response = await _dio.post<String>(
        pending.action.toString(),
        data: fields,
        options: _htmlOptions(
          headers: {
            'Referer': pending.pageUri.toString(),
            ...?_cookieHeaderMap(pending.cookies),
          },
        ),
      );
      if (!_isCurrentMfaChallenge(generation, pending)) {
        return _cancelledLoginResult;
      }
      _mergeCookies(pending.cookies, response.headers.map['set-cookie']);
      var redirect = _responseRedirect(response);
      for (var redirects = 0; redirect != null && redirects < 5; redirects++) {
        if (!_isNarouUri(redirect)) {
          _pendingMfa = null;
          return const NarouLoginResult.failure(
            '認証先を安全に確認できませんでした。ログインをやり直してください。',
          );
        }
        response = await _dio.get<String>(
          redirect.toString(),
          options: _htmlOptions(
            headers: {
              ...?_cookieHeaderMap(pending.cookies),
            },
          ),
        );
        if (!_isCurrentMfaChallenge(generation, pending)) {
          return _cancelledLoginResult;
        }
        _mergeCookies(pending.cookies, response.headers.map['set-cookie']);
        redirect = _responseRedirect(response);
      }
      if (redirect != null) {
        _pendingMfa = null;
        return const NarouLoginResult.failure(
          '認証画面への転送回数が上限を超えました。ログインをやり直してください。',
        );
      }

      final refreshedChallenge = _parseMfaChallenge(
        response.data ?? '',
        response.realUri,
        pending.cookies,
        pending.narouid,
      );
      if (!_isCurrentMfaChallenge(generation, pending)) {
        return _cancelledLoginResult;
      }
      if (refreshedChallenge != null) {
        _pendingMfa = refreshedChallenge;
        return const NarouLoginResult.failure(
          '認証コードを確認できませんでした。コードを確認して再入力してください。',
        );
      }

      var username = _extractUsername(response.data);
      if (response.statusCode != 200 ||
          !_isNarouUri(response.realUri) ||
          !_hasSessionCookies(pending.cookies)) {
        _pendingMfa = null;
        return const NarouLoginResult.failure(
          '認証コードを確認できませんでした。ログインをやり直してください。',
        );
      }

      if (username == null) {
        String? bookmarkHtml;
        if (_isAuthenticatedBookmarkListHtml(response.data)) {
          bookmarkHtml = response.data;
        } else {
          try {
            bookmarkHtml = await _fetchAuthenticatedBookmarkList(
              pending.cookies,
            );
          } on DioException catch (error) {
            if (!_isCurrentMfaChallenge(generation, pending)) {
              return _cancelledLoginResult;
            }
            _pendingMfa = null;
            debugPrint(
              '[NarouAuth] MFA後のセッション確認失敗 '
              'type=${error.type} status=${error.response?.statusCode}',
            );
            return const NarouLoginResult.failure(
              '認証後のセッションを確認できませんでした。ログインをやり直してください。',
            );
          }
          if (!_isCurrentMfaChallenge(generation, pending)) {
            return _cancelledLoginResult;
          }
        }

        if (bookmarkHtml == null) {
          _pendingMfa = null;
          return const NarouLoginResult.failure(
            '認証後のセッションを確認できませんでした。ログインをやり直してください。',
          );
        }
        username = _extractUsername(bookmarkHtml) ?? pending.narouid;
      }

      _pendingMfa = null;
      return _finishLogin(
        pending.cookies,
        pending.narouid,
        username,
        generation: generation,
      );
    } on DioException catch (e) {
      if (!_isCurrentMfaChallenge(generation, pending)) {
        return _cancelledLoginResult;
      }
      debugPrint(
        '[NarouAuth] MFA通信失敗 type=${e.type} status=${e.response?.statusCode}',
      );
      return const NarouLoginResult.failure('認証コードの送信に失敗しました');
    } on Object catch (e) {
      if (!_isCurrentMfaChallenge(generation, pending)) {
        return _cancelledLoginResult;
      }
      debugPrint('[NarouAuth] MFA処理失敗 type=${e.runtimeType}');
      return const NarouLoginResult.failure('認証コードの処理に失敗しました');
    }
  }

  /// 保存済みのセッションが有効か確認する。
  ///
  /// ブックマーク一覧ページへアクセスし、200が返れば有効と判断する。
  /// 302リダイレクト（ログインページへ転送）が返れば無効と判断する。
  Future<bool> isSessionValid() async {
    final cookieHeader = await authRepository.buildCookieHeader();
    if (cookieHeader == null) return false;

    try {
      final response = await _dio.get<String>(
        _bookmarkListUrl,
        options: Options(
          headers: {
            'User-Agent': narouUserAgent,
            'Cookie': cookieHeader,
          },
          followRedirects: false,
          validateStatus: (status) => status != null && status < 500,
          responseType: ResponseType.plain,
        ),
      );
      final data = response.data;
      if (response.statusCode != 200 || data == null) return false;
      return _isAuthenticatedBookmarkListHtml(data);
    } on Exception {
      return false;
    }
  }

  /// 保留中のMFAチャレンジと仮Cookieを破棄する。
  void cancelMfaChallenge() {
    _authOperationGeneration++;
    _pendingMfa?.cookies.clear();
    _pendingMfa = null;
  }

  /// ログアウトして保存済み認証情報をすべて削除する。
  Future<void> logout() async {
    cancelMfaChallenge();
    await _serializeSessionMutation(authRepository.clearAll);
  }

  /// ブックマーク一覧ページからユーザー名を取得する（ログイン後に呼ぶ）。
  Future<NarouLoginResult> _finishLogin(
    Map<String, String> cookies,
    String narouid,
    String username, {
    required int generation,
  }) async {
    var cancelled = false;
    var cleanedAfterCancellation = false;
    await _serializeSessionMutation(() async {
      if (!_isCurrentAuthOperation(generation)) {
        cancelled = true;
        return;
      }

      await authRepository.saveNarouid(narouid);
      if (!_isCurrentAuthOperation(generation)) {
        cancelled = true;
        cleanedAfterCancellation = true;
        await authRepository.clearAll();
        return;
      }

      await authRepository.saveUsername(username);
      if (!_isCurrentAuthOperation(generation)) {
        cancelled = true;
        cleanedAfterCancellation = true;
        await authRepository.clearAll();
        return;
      }

      await authRepository.saveSessionCookies(
        ks2: cookies['ks2']!,
        ses: cookies['ses']!,
        userl: cookies['userl']!,
      );
      if (!_isCurrentAuthOperation(generation)) {
        cancelled = true;
        cleanedAfterCancellation = true;
        await authRepository.clearAll();
      }
    });

    if (cancelled || !_isCurrentAuthOperation(generation)) {
      if (!cleanedAfterCancellation) {
        await _serializeSessionMutation(authRepository.clearAll);
      }
      return _cancelledLoginResult;
    }
    return NarouLoginResult.success(username: username);
  }

  Future<void> _serializeSessionMutation(
    Future<void> Function() mutation,
  ) {
    final operation = _sessionMutationQueue.then((_) => mutation());
    _sessionMutationQueue = operation.catchError((Object _) {});
    return operation;
  }

  bool _isCurrentAuthOperation(int generation) =>
      generation == _authOperationGeneration;

  bool _isCurrentMfaChallenge(
    int generation,
    _PendingNarouMfa pending,
  ) => _isCurrentAuthOperation(generation) && identical(_pendingMfa, pending);

  static const _cancelledLoginResult = NarouLoginResult.failure(
    'ログイン処理はキャンセルされました',
  );

  String? _extractUsername(String? html) {
    if (html == null || html.isEmpty) return null;
    final name = parser
        .parse(html)
        .querySelector('.p-up-header-pc__username')
        ?.text
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
    return name == null || name.isEmpty ? null : name;
  }

  bool _isAuthenticatedBookmarkListHtml(String? html) {
    if (html == null || html.isEmpty) return false;
    final document = parser.parse(html);
    final hasLoginForm =
        document.querySelector('form[action*="/login/login/"]') != null;
    final hasBookmarkPage =
        document.querySelector('.p-up-bookmark-item') != null ||
        html.contains('ブックマーク');
    return !hasLoginForm && hasBookmarkPage;
  }

  Future<String?> _fetchAuthenticatedBookmarkList(
    Map<String, String> cookies,
  ) async {
    final response = await _dio.get<String>(
      _bookmarkListUrl,
      options: _htmlOptions(headers: {...?_cookieHeaderMap(cookies)}),
    );
    if (response.statusCode != 200 || !_isNarouUri(response.realUri)) {
      return null;
    }
    final html = response.data;
    return _isAuthenticatedBookmarkListHtml(html) ? html : null;
  }

  Options _htmlOptions({Map<String, Object>? headers}) => Options(
    headers: {
      'User-Agent': narouUserAgent,
      'Content-Type': 'application/x-www-form-urlencoded',
      ...?headers,
    },
    followRedirects: false,
    validateStatus: (status) => status != null && status >= 200 && status < 400,
    responseType: ResponseType.plain,
  );

  Uri? _responseRedirect(Response<String> response) {
    final location = response.headers.value('location');
    if (location == null) return null;
    return response.realUri.resolve(location);
  }

  bool _isNarouUri(Uri uri) =>
      uri.scheme == 'https' &&
      uri.host == 'syosetu.com' &&
      uri.port == 443 &&
      uri.userInfo.isEmpty;

  bool _isNarouLoginAction(Uri uri) =>
      _isNarouUri(uri) && uri.path == Uri.parse(_loginUrl).path;

  bool _hasSessionCookies(Map<String, String> cookies) =>
      cookies['ks2']?.isNotEmpty == true &&
      cookies['ses']?.isNotEmpty == true &&
      cookies['userl']?.isNotEmpty == true;

  void _mergeCookies(Map<String, String> cookies, List<String>? headers) {
    if (headers == null) return;
    for (final header in headers) {
      final pair = header.split(';').first.trim();
      final separator = pair.indexOf('=');
      if (separator <= 0) continue;
      final name = pair.substring(0, separator).trim();
      final value = pair.substring(separator + 1).trim();
      if (name.isEmpty) continue;
      if (_isExpiredCookie(header, value)) {
        cookies.remove(name);
      } else {
        cookies[name] = value;
      }
    }
  }

  bool _isExpiredCookie(String header, String value) {
    if (value.isEmpty) return true;
    for (final attribute in header.split(';').skip(1)) {
      final trimmedAttribute = attribute.trim();
      final normalized = trimmedAttribute.toLowerCase();
      if (normalized.startsWith('max-age=')) {
        final maxAge = int.tryParse(normalized.substring('max-age='.length));
        if (maxAge != null && maxAge <= 0) return true;
      }
      if (normalized.startsWith('expires=')) {
        final expiresAt = _parseCookieExpiration(
          trimmedAttribute.substring('expires='.length).trim(),
        );
        if (expiresAt != null && !expiresAt.isAfter(DateTime.now().toUtc())) {
          return true;
        }
      }
    }
    return false;
  }

  DateTime? _parseCookieExpiration(String value) {
    final match = RegExp(
      r'^(?:[a-z]{3},\s*)?(\d{1,2})[\s-]+([a-z]{3})[\s-]'
      r'(\d{4})\s+(\d{2}):(\d{2}):(\d{2})\s+gmt$',
      caseSensitive: false,
    ).firstMatch(value);
    if (match == null) return null;
    final month = _cookieMonths[match.group(2)!.toLowerCase()];
    if (month == null) return null;
    return DateTime.utc(
      int.parse(match.group(3)!),
      month,
      int.parse(match.group(1)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
      int.parse(match.group(6)!),
    );
  }

  _PendingNarouMfa? _parseMfaChallenge(
    String html,
    Uri pageUri,
    Map<String, String> cookies,
    String narouid,
  ) {
    if (!_isNarouUri(pageUri)) return null;
    final document = parser.parse(html);
    final pageText = document.body?.text.toLowerCase() ?? '';
    final hasCodePrompt =
        pageText.contains('認証コード') ||
        pageText.contains('二段階認証') ||
        pageText.contains('2段階認証') ||
        pageText.contains('ワンタイム');
    if (!hasCodePrompt) return null;

    final forms = document.querySelectorAll('form');
    Element? form;
    for (final candidate in forms) {
      if (_codeInput(candidate) != null) {
        form = candidate;
        break;
      }
    }
    if (form == null) return null;
    final codeInput = _codeInput(form)!;
    final codeField = codeInput.attributes['name'];
    if (codeField == null || codeField.isEmpty) return null;
    final action = _formAction(form, pageUri, fallback: pageUri);
    if (!_isNarouUri(action)) return null;
    return _PendingNarouMfa(
      action: action,
      pageUri: pageUri,
      codeField: codeField,
      hiddenFields: _hiddenFields(form),
      cookies: Map<String, String>.of(cookies),
      narouid: narouid,
    );
  }

  Element? _codeInput(Element form) {
    for (final input in form.querySelectorAll('input')) {
      final type = input.attributes['type']?.toLowerCase();
      if (type == 'hidden' || type == 'submit' || type == 'button') continue;
      final nameAndLabels = <String>[
        input.attributes['name'] ?? '',
        input.attributes['id'] ?? '',
        input.attributes['aria-label'] ?? '',
        input.attributes['placeholder'] ?? '',
      ].join(' ').toLowerCase();
      final autocomplete = input.attributes['autocomplete']?.toLowerCase();
      final codeFieldPattern = RegExp(
        '(^|[^a-z0-9])'
        '(otp|auth[_-]?code|mfa[_-]?code|verification[_-]?code|'
        'security[_-]?code|confirmation[_-]?code)'
        '([^a-z0-9]|(?![a-z0-9]))',
      );
      final hasCodeMarker =
          autocomplete == 'one-time-code' ||
          codeFieldPattern.hasMatch(nameAndLabels) ||
          nameAndLabels.contains('認証コード') ||
          nameAndLabels.contains('確認コード') ||
          nameAndLabels.contains('ワンタイム');
      if (hasCodeMarker) {
        return input;
      }
    }
    return null;
  }

  Element? _findForm(Document document, List<String> inputNames) {
    for (final form in document.querySelectorAll('form')) {
      if (inputNames.every(
        (name) => form.querySelector('input[name="$name"]') != null,
      )) {
        return form;
      }
    }
    return null;
  }

  Map<String, String> _hiddenFields(Element form) {
    final fields = <String, String>{};
    for (final input in form.querySelectorAll('input[type="hidden"][name]')) {
      final name = input.attributes['name'];
      if (name == null || name.isEmpty) continue;
      fields[name] = input.attributes['value'] ?? '';
    }
    return fields;
  }

  Uri _formAction(Element form, Uri pageUri, {required Uri fallback}) {
    final action = form.attributes['action'];
    return action == null || action.isEmpty
        ? fallback
        : pageUri.resolve(action);
  }

  String? _buildCookieHeader(Map<String, String> cookies) => cookies.isEmpty
      ? null
      : cookies.entries
            .map((entry) => '${entry.key}=${entry.value}')
            .join('; ');

  Map<String, String>? _cookieHeaderMap(Map<String, String> cookies) {
    final header = _buildCookieHeader(cookies);
    return header == null ? null : {'Cookie': header};
  }
}

class _PendingNarouMfa {
  _PendingNarouMfa({
    required this.action,
    required this.pageUri,
    required this.codeField,
    required this.hiddenFields,
    required this.cookies,
    required this.narouid,
  });

  final Uri action;
  final Uri pageUri;
  final String codeField;
  final Map<String, String> hiddenFields;
  final Map<String, String> cookies;
  final String narouid;
}

/// ログイン処理の結果を表すクラス。
class NarouLoginResult {
  /// ログイン成功。
  const NarouLoginResult.success({required this.username})
    : isSuccess = true,
      requiresMfa = false,
      error = null;

  /// 二段階認証コードの入力待ち。
  const NarouLoginResult.mfaRequired()
    : isSuccess = false,
      requiresMfa = true,
      username = null,
      error = null;

  /// ログイン失敗。
  const NarouLoginResult.failure(String this.error)
    : isSuccess = false,
      requiresMfa = false,
      username = null;

  /// 成功したか否か。
  final bool isSuccess;

  /// 二段階認証コードの入力が必要か。
  final bool requiresMfa;

  /// ログイン成功時のユーザー名。
  final String? username;

  /// ログイン失敗時のエラーメッセージ。
  final String? error;
}
