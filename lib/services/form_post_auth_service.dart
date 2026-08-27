import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:novelty/repositories/form_auth_session_repository.dart';
import 'package:novelty/utils/auth_failure_message.dart';

/// フォームPOSTログインのサイト別仕様。
class FormPostAuthConfiguration {
  /// コンストラクタ。
  const FormPostAuthConfiguration({
    required this.loginUri,
    required this.postUri,
    required this.accountField,
    required this.passwordField,
    required this.hiddenFields,
    this.staticFields = const {},
    this.sessionCheckUri,
  });

  /// ログインフォーム取得先。
  final Uri loginUri;

  /// セッション有効性の確認先。未指定なら[loginUri]を使う。
  ///
  /// ログイン済みでもログインページを200で返すサイトでは、[loginUri]を見ても
  /// ログイン状態を判別できない。その場合は未ログイン時にログインページへ
  /// リダイレクトする要認証URLを指定する。
  final Uri? sessionCheckUri;

  /// フォーム送信先。
  final Uri postUri;

  /// アカウント入力欄のname。
  final String accountField;

  /// パスワード入力欄のname。
  final String passwordField;

  /// HTMLから取得する必須hidden field名。
  final List<String> hiddenFields;

  /// 実測済みの固定field。
  final Map<String, String> staticFields;
}

/// フォームPOSTログイン結果。
class FormAuthLoginResult {
  /// 成功。
  const FormAuthLoginResult.success() : isSuccess = true, error = null;

  /// 失敗。
  const FormAuthLoginResult.failure(this.error) : isSuccess = false;

  /// 成功したか。
  final bool isSuccess;

  /// 失敗理由。
  final String? error;
}

/// 実測済みフォーム仕様だけを使う共通認証処理。
class FormPostAuthService {
  /// コンストラクタ。
  FormPostAuthService({
    required FormAuthSessionRepository sessionRepository,
    required Dio dio,
    required FormPostAuthConfiguration configuration,
  }) : _sessionRepository = sessionRepository,
       _dio = dio,
       _configuration = configuration;

  final FormAuthSessionRepository _sessionRepository;
  final Dio _dio;
  final FormPostAuthConfiguration _configuration;

  /// デバッグログの見出し。どのサイトのログか区別する。
  String get _logTag => '[FormAuth:${_configuration.loginUri.host}]';

  /// ログインフォームを取得して送信し、発行された全Cookieを保存する。
  Future<FormAuthLoginResult> login({
    required String accountId,
    required String password,
  }) async {
    try {
      final loginResponse = await _dio.get<String>(
        _configuration.loginUri.toString(),
        options: _plainHtmlOptions(),
      );
      final loginHtml = loginResponse.data;
      debugPrint(
        '$_logTag login: フォーム取得 status=${loginResponse.statusCode} '
        'body=${loginHtml?.length ?? 0}文字',
      );
      if (loginResponse.statusCode != 200 || loginHtml == null) {
        return const FormAuthLoginResult.failure('ログイン画面を取得できませんでした');
      }

      final document = html_parser.parse(loginHtml);
      final fields = <String, String>{};
      for (final name in _configuration.hiddenFields) {
        final value = document
            .querySelector('input[name="$name"]')
            ?.attributes['value'];
        if (value == null || value.isEmpty) {
          debugPrint('$_logTag login: hidden field "$name" が見つかりません');
          return const FormAuthLoginResult.failure('ログイン画面の認証情報を取得できませんでした');
        }
        fields[name] = value;
      }
      fields
        ..addAll(_configuration.staticFields)
        ..[_configuration.accountField] = accountId
        ..[_configuration.passwordField] = password;

      final cookies = <String, String>{};
      _applySetCookies(cookies, loginResponse.headers.map['set-cookie']);
      final cookieHeader = _buildCookieHeader(cookies);
      debugPrint(
        '$_logTag login: 送信field=${fields.keys.toList()} '
        'GET由来Cookie=${cookies.keys.toList()}',
      );

      final postResponse = await _dio.post<String>(
        _configuration.postUri.toString(),
        data: fields,
        options: _plainHtmlOptions(
          headers: cookieHeader == null ? null : {'Cookie': cookieHeader},
        ),
      );
      final postCookies = <String, String>{};
      _applySetCookies(
        postCookies,
        postResponse.headers.map['set-cookie'],
      );

      debugPrint(
        '$_logTag login: POST status=${postResponse.statusCode} '
        'location=${postResponse.headers.value('location')} '
        'POST由来Cookie=${postCookies.keys.toList()} '
        'body=${postResponse.data?.length ?? 0}文字',
      );

      if (!_indicatesLoginSuccess(postResponse, postCookies)) {
        return const FormAuthLoginResult.failure('ログインに失敗しました。入力内容を確認してください');
      }

      _applySetCookies(cookies, postResponse.headers.map['set-cookie']);
      await _sessionRepository.saveSession(
        accountId: accountId,
        cookies: cookies,
      );
      debugPrint(
        '$_logTag login: 成功。保存Cookie=${cookies.keys.toList()}',
      );
      return const FormAuthLoginResult.success();
    } on DioException catch (error) {
      debugPrint(
        '$_logTag login: DioException type=${error.type} '
        'status=${error.response?.statusCode} message=${error.message}',
      );
      return FormAuthLoginResult.failure(
        error.message ?? 'ネットワークエラーが発生しました',
      );
    } on Object catch (error, stackTrace) {
      debugPrint('$_logTag login: 例外 ${error.runtimeType}: $error');
      debugPrint('$_logTag login: $stackTrace');
      // Secure Storage の失敗など DioException 以外も失敗として返す。
      // ここで throw すると呼び出し元の進捗表示が解除されない。
      return FormAuthLoginResult.failure(describeAuthFailure(error));
    }
  }

  /// 保存済みセッションが有効か要認証ページで確認する。
  Future<bool> isSessionValid() async {
    final cookieHeader = await _sessionRepository.buildCookieHeader();
    if (cookieHeader == null || cookieHeader.isEmpty) {
      debugPrint('$_logTag isSessionValid: 保存Cookieなし');
      return false;
    }

    final checkUri = _configuration.sessionCheckUri ?? _configuration.loginUri;
    final checksLoginPage = checkUri == _configuration.loginUri;

    try {
      final response = await _dio.get<String>(
        checkUri.toString(),
        options: _plainHtmlOptions(headers: {'Cookie': cookieHeader}),
      );
      final status = response.statusCode;
      final location = response.headers.value('location');
      debugPrint(
        '$_logTag isSessionValid: status=$status location=$location '
        'body=${response.data?.length ?? 0}文字',
      );
      if (status == null || status < 200 || status >= 400) return false;

      if (location != null) {
        final result = _redirectsAwayFromLogin(location);
        debugPrint('$_logTag isSessionValid: リダイレクト判定=$result');
        return result;
      }

      final body = response.data;
      if (body == null || body.isEmpty) return false;
      final document = html_parser.parse(body);
      final hasForm = _containsLoginForm(document);
      if (hasForm) {
        debugPrint('$_logTag isSessionValid: ログインフォームが表示されている');
        return false;
      }
      // 要認証URLを指定している場合、リダイレクトされずに本文を取得できた
      // 時点でログイン済み。ここでエラー表示を探すと、通常ページに含まれる
      // `.error` などを誤検出して未ログイン扱いになる。
      if (!checksLoginPage) return true;

      final hasError = _containsLoginError(document);
      debugPrint('$_logTag isSessionValid: エラー表示=$hasError');
      return !hasError;
    } on Exception catch (e) {
      debugPrint('$_logTag isSessionValid: 例外 ${e.runtimeType}: $e');
      return false;
    }
  }

  /// 保存済み認証情報を削除する。
  Future<void> logout() => _sessionRepository.clearAll();

  Options _plainHtmlOptions({Map<String, Object>? headers}) => Options(
    headers: headers,
    contentType: Headers.formUrlEncodedContentType,
    followRedirects: false,
    validateStatus: (status) => status != null && status >= 200 && status < 400,
    responseType: ResponseType.plain,
  );

  bool _indicatesLoginSuccess(
    Response<String> response,
    Map<String, String> postCookies,
  ) {
    final status = response.statusCode;
    if (status == null || status < 200 || status >= 400) return false;

    // 成功時Cookie名と成功HTMLは実機ログインまで未確認。
    // Cookie名を限定せず、POST後のCookie発行に加えてログインフォームや
    // エラーが再表示されていない場合だけ成功とする。実機確認後に差し替える。
    if (postCookies.isEmpty) {
      debugPrint('$_logTag 成功判定: POST後のCookieが空');
      return false;
    }

    final body = response.data ?? '';
    if (body.isNotEmpty) {
      final document = html_parser.parse(body);
      final hasForm = _containsLoginForm(document);
      final hasError = _containsLoginError(document);
      debugPrint(
        '$_logTag 成功判定: ログインフォーム=$hasForm エラー表示=$hasError',
      );
      if (hasForm || hasError) return false;
    }

    final location = response.headers.value('location');
    if (location != null) {
      final result = _redirectsAwayFromLogin(location);
      debugPrint('$_logTag 成功判定: リダイレクト判定=$result');
      return result;
    }
    return body.isNotEmpty;
  }

  bool _containsLoginForm(Document document) {
    return document
        .querySelectorAll('form')
        .any(
          (form) =>
              form.querySelector(
                    'input[name="${_configuration.accountField}"]',
                  ) !=
                  null &&
              form.querySelector(
                    'input[name="${_configuration.passwordField}"]',
                  ) !=
                  null,
        );
  }

  bool _containsLoginError(Document document) {
    const selectors = <String>[
      '.alert-danger',
      '.error',
      '.errors',
      '.invalid-feedback',
      '[role="alert"]',
    ];
    if (selectors.any((selector) => document.querySelector(selector) != null)) {
      return true;
    }
    final text = document.body?.text ?? '';
    return text.contains('ログインに失敗') ||
        text.contains('認証に失敗') ||
        text.contains('正しくありません');
  }

  bool _redirectsAwayFromLogin(String location) {
    final target = _configuration.postUri.resolve(location);
    if (target.host != _configuration.loginUri.host) return false;
    if (target.path == _configuration.loginUri.path &&
        target.query == _configuration.loginUri.query) {
      return false;
    }
    final mode = target.queryParameters['mode'];
    return mode == null || !mode.startsWith('login');
  }

  void _applySetCookies(
    Map<String, String> cookies,
    List<String>? setCookieHeaders,
  ) {
    if (setCookieHeaders == null) return;
    for (final header in setCookieHeaders) {
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

  String? _buildCookieHeader(Map<String, String> cookies) => cookies.isEmpty
      ? null
      : cookies.entries
            .map((entry) => '${entry.key}=${entry.value}')
            .join('; ');
}
