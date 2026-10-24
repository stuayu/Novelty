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

  /// ログインPOSTリクエストを送信し、セッションCookieを取得・保存する。
  ///
  /// 成功した場合は`NarouLoginResult.success`を返す。
  /// 失敗した場合はエラーメッセージを含む`NarouLoginResult.failure`を返す。
  Future<NarouLoginResult> login({
    required String narouid,
    required String password,
  }) async {
    _pendingMfa = null;
    try {
      final formResponse = await _dio.get<String>(
        _loginInputUrl,
        options: _htmlOptions(),
      );
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
      if (!_isNarouUri(loginAction)) {
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
      if (pending == null) {
        return const NarouLoginResult.failure(
          'ログインに失敗しました。入力内容を確認してください。',
        );
      }
      _pendingMfa = pending;
      return const NarouLoginResult.mfaRequired();
    } on DioException catch (e) {
      debugPrint(
        '[NarouAuth] login: 通信失敗 '
        'type=${e.type} status=${e.response?.statusCode}',
      );
      return const NarouLoginResult.failure('ログイン通信に失敗しました');
    } on Object catch (e) {
      debugPrint('[NarouAuth] login: 処理失敗 type=${e.runtimeType}');
      return const NarouLoginResult.failure('ログイン処理に失敗しました');
    }
  }

  /// メールまたは認証アプリで受け取った確認コードを一度だけ送信する。
  Future<NarouLoginResult> verifyMfaCode(String code) async {
    final pending = _pendingMfa;
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
      _mergeCookies(pending.cookies, response.headers.map['set-cookie']);
      var redirect = _responseRedirect(response);
      for (
        var redirects = 0;
        !_hasSessionCookies(pending.cookies) &&
            redirect != null &&
            redirects < 5;
        redirects++
      ) {
        if (!_isNarouUri(redirect)) {
          _pendingMfa = null;
          return const NarouLoginResult.failure('認証先を安全に確認できませんでした');
        }
        response = await _dio.get<String>(
          redirect.toString(),
          options: _htmlOptions(
            headers: {
              ...?_cookieHeaderMap(pending.cookies),
            },
          ),
        );
        _mergeCookies(pending.cookies, response.headers.map['set-cookie']);
        redirect = _responseRedirect(response);
      }
      if (!_hasSessionCookies(pending.cookies)) {
        if (redirect != null && !_isNarouUri(redirect)) {
          _pendingMfa = null;
          return const NarouLoginResult.failure('認証先を安全に確認できませんでした');
        }
        return const NarouLoginResult.failure(
          '認証コードを確認できませんでした。コードを確認して再入力してください。',
        );
      }

      _pendingMfa = null;
      return _finishLogin(pending.cookies, pending.narouid);
    } on DioException catch (e) {
      debugPrint(
        '[NarouAuth] MFA通信失敗 type=${e.type} status=${e.response?.statusCode}',
      );
      return const NarouLoginResult.failure('認証コードの送信に失敗しました');
    } on Object catch (e) {
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
      final doc = parser.parse(data);
      final hasLoginForm =
          doc.querySelector('form[action*="/login/login/"]') != null;
      final hasBookmarkPage =
          doc.querySelector('.p-up-bookmark-item') != null ||
          data.contains('ブックマーク');
      return !hasLoginForm && hasBookmarkPage;
    } on Exception {
      return false;
    }
  }

  /// ログアウトして保存済み認証情報をすべて削除する。
  Future<void> logout() => authRepository.clearAll();

  /// ブックマーク一覧ページからユーザー名を取得する（ログイン後に呼ぶ）。
  Future<String?> _fetchUsername({
    required String ks2,
    required String ses,
    required String userl,
  }) async {
    try {
      final response = await _dio.get<String>(
        _bookmarkListUrl,
        options: Options(
          headers: {
            'User-Agent': narouUserAgent,
            'Cookie': 'ks2=$ks2; ses=$ses; userl=$userl',
          },
          followRedirects: false,
          responseType: ResponseType.plain,
        ),
      );
      if (response.data == null) return null;
      final responseData = response.data!;
      final doc = parser.parse(responseData);
      // ユーザー名は `.p-up-header-pc__username` から取得
      final nameEl = doc.querySelector('.p-up-header-pc__username');
      return nameEl?.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    } on Exception catch (e) {
      debugPrint('[NarouAuth] ユーザー名取得失敗 type=${e.runtimeType}');
      return null;
    }
  }

  Future<NarouLoginResult> _finishLogin(
    Map<String, String> cookies,
    String narouid,
  ) async {
    final username =
        await _fetchUsername(
          ks2: cookies['ks2']!,
          ses: cookies['ses']!,
          userl: cookies['userl']!,
        ) ??
        narouid;
    await authRepository.saveNarouid(narouid);
    await authRepository.saveUsername(username);
    await authRepository.saveSessionCookies(
      ks2: cookies['ks2']!,
      ses: cookies['ses']!,
      userl: cookies['userl']!,
    );
    return NarouLoginResult.success(username: username);
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
      if (value.isEmpty || header.toLowerCase().contains('max-age=0')) {
        cookies.remove(name);
      } else {
        cookies[name] = value;
      }
    }
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
      final attributes = <String>[
        input.attributes['name'] ?? '',
        input.attributes['id'] ?? '',
        input.attributes['autocomplete'] ?? '',
        input.attributes['aria-label'] ?? '',
        input.attributes['placeholder'] ?? '',
      ].join(' ').toLowerCase();
      if (attributes.contains('one-time-code') ||
          attributes.contains('otp') ||
          attributes.contains('code') ||
          attributes.contains('認証') ||
          attributes.contains('確認')) {
        return input;
      }
      if (type == 'number' || type == 'tel') return input;
    }
    final visibleInputs = form
        .querySelectorAll('input')
        .where((input) => input.attributes['type']?.toLowerCase() != 'hidden')
        .toList();
    if (visibleInputs.length == 1) return visibleInputs.single;
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
