import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as parser;
import 'package:novelty/providers/site_rate_limiter_provider.dart';
import 'package:novelty/repositories/auth_repository.dart';
import 'package:novelty/services/http_client.dart';
import 'package:novelty/services/narou_auth_diagnostics.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:novelty/utils/http_cookie.dart';
import 'package:novelty/utils/narou_uri_utils.dart';
import 'package:novelty/utils/request_rate_limiter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
part 'narou_auth_service.g.dart';

const _loginUrl = 'https://syosetu.com/login/login/';
const _loginInputUrl = 'https://syosetu.com/login/input/';
const _bookmarkListUrl = 'https://syosetu.com/favnovelmain/list/';

/// 保存済みセッションの検証結果。
enum NarouSessionValidity {
  /// 認証済みページを確認できた。
  valid,

  /// なろうのログイン画面を確認した。
  invalid,

  /// 通信エラーなどにより状態を確認できなかった。
  unavailable,
}

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
    diagnostics: narouAuthDiagnosticsLogger,
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
    NarouAuthDiagnosticsLogger? diagnostics,
  }) : _dio =
           dio ??
           createNoveltyDio(
             rateLimiter: rateLimiter,
           ),
       _diagnostics = diagnostics ?? NarouAuthDiagnosticsLogger(enabled: false);

  /// 認証情報リポジトリ。
  final AuthRepository authRepository;

  /// HTTPクライアント。レート制限とタイムアウトは共通ファクトリで設定する。
  final Dio _dio;
  final NarouAuthDiagnosticsLogger _diagnostics;
  _PendingNarouMfa? _pendingMfa;
  int _authOperationGeneration = 0;
  int _httpRequestSequence = 0;
  Future<void> _sessionMutationQueue = Future<void>.value();

  /// 開発用の診断ログが有効かどうか。
  bool get diagnosticsEnabled => _diagnostics.enabled;

  /// 認証処理に関連する診断イベントを記録する。
  void recordDiagnosticEvent(
    String operationId,
    String event, [
    Map<String, Object?> fields = const <String, Object?>{},
  ]) => _log(operationId, event, fields);

  /// 認証後の補助処理を相関させる操作IDを生成する。
  String createDiagnosticOperationId() => _diagnostics.createOperationId();

  /// 診断ログファイルへの書き込みを完了してパスを返す。
  Future<String?> diagnosticsLogFilePath() async {
    await _diagnostics.flush();
    return _diagnostics.logFilePath();
  }

  void _log(
    String operationId,
    String event, [
    Map<String, Object?> fields = const <String, Object?>{},
  ]) {
    _diagnostics.record(operationId, event, fields);
  }

  Future<Response<String>> _sendDiagnosticRequest({
    required String operationId,
    required String method,
    required Uri requestUri,
    required Future<Response<String>> Function() send,
    Map<String, String>? cookies,
    Iterable<String>? fieldNames,
  }) async {
    final requestSequence = ++_httpRequestSequence;
    final route = _diagnosticRoute(requestUri);
    final stopwatch = Stopwatch()..start();
    _log(operationId, 'http.request', <String, Object?>{
      'sequence': requestSequence,
      'method': method,
      'route': route,
      'trustedOrigin': _isNarouUri(requestUri),
      if (cookies != null) ..._diagnosticCookieMetadata(cookies),
      if (fieldNames != null)
        'formFieldNames': _safeDiagnosticNames(fieldNames),
    });
    try {
      final response = await send();
      stopwatch.stop();
      final redirect = _responseRedirect(response);
      _log(operationId, 'http.response', <String, Object?>{
        'sequence': requestSequence,
        'method': method,
        'requestRoute': route,
        'responseRoute': _diagnosticRoute(response.realUri),
        'trustedOrigin': _isNarouUri(response.realUri),
        'status': response.statusCode,
        'durationMs': stopwatch.elapsedMilliseconds,
        'responseBytes': _responseBytes(response.data),
        'contentType': _diagnosticContentType(
          response.headers.value('content-type'),
        ),
        'setCookieNames': _cookieNamesFromHeaders(
          response.headers.map['set-cookie'],
        ),
        'redirectRoute': redirect == null ? null : _diagnosticRoute(redirect),
        'redirectTrusted': redirect == null ? null : _isNarouUri(redirect),
      });
      return response;
    } on DioException catch (error) {
      stopwatch.stop();
      final errorResponse = error.response;
      final redirect = errorResponse == null
          ? null
          : _responseRedirect(errorResponse);
      _log(operationId, 'http.error', <String, Object?>{
        'sequence': requestSequence,
        'method': method,
        'requestRoute': route,
        'errorType': error.type.name,
        'status': errorResponse?.statusCode,
        'responseRoute': errorResponse == null
            ? null
            : _diagnosticRoute(errorResponse.realUri),
        'durationMs': stopwatch.elapsedMilliseconds,
        'responseBytes': errorResponse == null
            ? null
            : _responseBytes(errorResponse.data),
        'contentType': errorResponse == null
            ? null
            : _diagnosticContentType(
                errorResponse.headers.value('content-type'),
              ),
        'redirectRoute': redirect == null ? null : _diagnosticRoute(redirect),
        'redirectTrusted': redirect == null ? null : _isNarouUri(redirect),
      });
      rethrow;
    } on Object catch (error) {
      stopwatch.stop();
      _log(operationId, 'http.error', <String, Object?>{
        'sequence': requestSequence,
        'method': method,
        'requestRoute': route,
        'errorType': error.runtimeType.toString(),
        'durationMs': stopwatch.elapsedMilliseconds,
      });
      rethrow;
    }
  }

  String _diagnosticRoute(Uri uri) {
    if (!_isNarouUri(uri)) return 'external-or-untrusted';
    final path = uri.path;
    if (path == Uri.parse(_loginInputUrl).path) return 'login-input';
    if (path == Uri.parse(_loginUrl).path) return 'login-submit';
    if (path == '/login/auth_code/verify/') return 'legacy-mfa-submit';
    if (path == '/login/user2stepauthend/') return 'mfa-complete';
    if (_isNarouUserTopUri(uri)) return 'user-top';
    if (_isNarouBookmarkListUri(uri)) return 'bookmark-list';
    if (path.startsWith('/user2stepauth/input/')) return 'mfa-choice';
    if (path.startsWith('/user2stepauth/totpinput/')) return 'mfa-totp-page';
    if (path.startsWith('/user2stepauth/emailinput/')) {
      return 'mfa-email-page';
    }
    if (path.startsWith('/user2stepauth/totpauth/')) {
      return 'mfa-totp-submit';
    }
    if (path.startsWith('/user2stepauth/emailauth/')) {
      return 'mfa-email-submit';
    }
    if (path.startsWith('/user2stepauth/sendemail/')) {
      return 'mfa-email-send';
    }
    if (path.startsWith('/login/')) return 'login-other';
    return 'narou-other';
  }

  Map<String, Object?> _diagnosticCookieMetadata(
    Map<String, String> cookies,
  ) => <String, Object?>{
    'cookieNames': _safeDiagnosticNames(cookies.keys),
    'cookieCount': cookies.length,
    'requiredSessionCookies': _sessionCookiePresence(cookies),
  };

  Map<String, bool> _sessionCookiePresence(Map<String, String> cookies) =>
      <String, bool>{
        for (final name in const <String>['ks2', 'ses', 'userl'])
          name: cookies[name]?.isNotEmpty == true,
      };

  List<String> _safeDiagnosticNames(Iterable<String> names) =>
      names
          .map((name) => name.trim())
          .where((name) => RegExp(r'^[A-Za-z0-9_-]{1,48}$').hasMatch(name))
          .toSet()
          .toList()
        ..sort();

  List<String> _cookieNamesFromHeaders(List<String>? headers) {
    if (headers == null) return const <String>[];
    return _safeDiagnosticNames(
      headers.map((header) {
        final pair = header.split(';').first.split('=');
        return pair.isEmpty ? '' : pair.first;
      }),
    );
  }

  int _responseBytes(Object? body) => switch (body) {
    final String value => utf8.encode(value).length,
    final List<int> value => value.length,
    null => 0,
    _ => 0,
  };

  String _diagnosticContentType(String? contentType) {
    final normalized = contentType?.toLowerCase() ?? '';
    if (normalized.contains('html')) return 'html';
    if (normalized.contains('json')) return 'json';
    if (normalized.startsWith('text/')) return 'text';
    return normalized.isEmpty ? 'missing' : 'other';
  }

  String _diagnosticCodeFieldClass(String name) {
    final normalized = name.toLowerCase();
    if (normalized.contains('totp') || normalized.contains('otp')) {
      return 'totp';
    }
    if (normalized.contains('email') || normalized.contains('mail')) {
      return 'email';
    }
    return 'other';
  }

  /// ログインPOSTリクエストを送信し、セッションCookieを取得・保存する。
  ///
  /// 成功した場合は`NarouLoginResult.success`を返す。
  /// 失敗した場合はエラーメッセージを含む`NarouLoginResult.failure`を返す。
  Future<NarouLoginResult> login({
    required String narouid,
    required String password,
    bool rememberSession = true,
  }) async {
    final operationId = _diagnostics.createOperationId();
    _log(operationId, 'login.started', <String, Object?>{
      'rememberSession': rememberSession,
      'requiredMfa': true,
    });
    _discardMfaChallenge(reason: 'superseded-by-new-login');
    final generation = _authOperationGeneration;
    try {
      final formResponse = await _sendDiagnosticRequest(
        operationId: operationId,
        method: 'GET',
        requestUri: Uri.parse(_loginInputUrl),
        send: () => _dio.get<String>(
          _loginInputUrl,
          options: _htmlOptions(),
        ),
      );
      if (!_isCurrentAuthOperation(generation)) {
        _log(operationId, 'login.cancelled', <String, Object?>{
          'stage': 'login-form-response',
        });
        return _cancelledLoginResult;
      }
      final loginDocument = parser.parse(formResponse.data ?? '');
      final loginForm = _findForm(loginDocument, [
        'narouid',
        'pass',
      ]);
      if (loginForm == null) {
        _log(operationId, 'login.form.parse', <String, Object?>{
          'result': 'missing',
          'formCount': loginDocument.querySelectorAll('form').length,
          'narouIdFieldPresent':
              loginDocument.querySelector('input[name="narouid"]') != null,
          'passwordFieldPresent':
              loginDocument.querySelector('input[name="pass"]') != null,
        });
        _log(operationId, 'login.result', <String, Object?>{
          'outcome': 'failure',
          'reason': 'login-form-missing',
        });
        return const NarouLoginResult.failure('ログイン画面の認証情報を取得できませんでした');
      }

      final prevalidatedLoginAction = _formAction(
        loginForm,
        formResponse.realUri,
        fallback: Uri.parse(_loginUrl),
      );
      _log(operationId, 'login.form.parse', <String, Object?>{
        'result': 'found',
        'formCount': loginDocument.querySelectorAll('form').length,
        'actionRoute': _diagnosticRoute(prevalidatedLoginAction),
        'hiddenFieldNames': _safeDiagnosticNames(
          _hiddenFields(loginForm).keys,
        ),
        'persistentLoginFieldNames': _safeDiagnosticNames(
          _persistentLoginFields(loginForm, rememberSession).keys,
        ),
      });

      final cookies = <String, String>{};
      mergeSetCookieHeaders(cookies, formResponse.headers.map['set-cookie']);
      final loginFields = _hiddenFields(loginForm)
        ..addAll(_persistentLoginFields(loginForm, rememberSession))
        ..['narouid'] = narouid
        ..['pass'] = password;
      final loginAction = _formAction(
        loginForm,
        formResponse.realUri,
        fallback: Uri.parse(_loginUrl),
      );
      if (!_isNarouLoginAction(loginAction)) {
        _log(operationId, 'login.form.rejected', <String, Object?>{
          'reason': 'untrusted-action',
          'actionRoute': _diagnosticRoute(loginAction),
          'trustedAction': _isNarouUri(loginAction),
        });
        _log(operationId, 'login.result', <String, Object?>{
          'outcome': 'failure',
          'reason': 'untrusted-login-action',
        });
        return const NarouLoginResult.failure('ログイン先を安全に確認できませんでした');
      }

      final response = await _sendDiagnosticRequest(
        operationId: operationId,
        method: 'POST',
        requestUri: loginAction,
        cookies: cookies,
        fieldNames: loginFields.keys,
        send: () => _dio.post<String>(
          loginAction.toString(),
          data: loginFields,
          options: _htmlOptions(
            headers: {
              'Referer': _loginInputUrl,
              ...?_cookieHeaderMap(cookies),
            },
          ),
        ),
      );
      if (!_isCurrentAuthOperation(generation)) {
        _log(operationId, 'login.cancelled', <String, Object?>{
          'stage': 'credential-response',
        });
        return _cancelledLoginResult;
      }
      mergeSetCookieHeaders(cookies, response.headers.map['set-cookie']);
      var challengeUri = _responseRedirect(response);
      Response<String>? challengeResponse;
      for (
        var redirects = 0;
        challengeUri != null && redirects < 5;
        redirects++
      ) {
        if (!_isNarouUri(challengeUri)) {
          _log(operationId, 'login.redirect.rejected', <String, Object?>{
            'hop': redirects + 1,
            'trustedTarget': false,
            'targetRoute': _diagnosticRoute(challengeUri),
          });
          _log(operationId, 'login.result', <String, Object?>{
            'outcome': 'failure',
            'reason': 'untrusted-redirect',
          });
          return const NarouLoginResult.failure('認証先を安全に確認できませんでした');
        }
        _log(operationId, 'login.redirect.follow', <String, Object?>{
          'hop': redirects + 1,
          'targetRoute': _diagnosticRoute(challengeUri),
          'trustedTarget': true,
        });
        challengeResponse = await _sendDiagnosticRequest(
          operationId: operationId,
          method: 'GET',
          requestUri: challengeUri,
          cookies: cookies,
          send: () => _dio.get<String>(
            challengeUri.toString(),
            options: _htmlOptions(
              headers: {
                ...?_cookieHeaderMap(cookies),
              },
            ),
          ),
        );
        if (!_isCurrentAuthOperation(generation)) {
          _log(operationId, 'login.cancelled', <String, Object?>{
            'stage': 'redirect-response',
          });
          return _cancelledLoginResult;
        }
        mergeSetCookieHeaders(
          cookies,
          challengeResponse.headers.map['set-cookie'],
        );
        challengeUri = _responseRedirect(challengeResponse);
      }
      if (challengeUri != null) {
        _log(operationId, 'login.result', <String, Object?>{
          'outcome': 'failure',
          'reason': 'redirect-limit',
          'redirectLimit': 5,
        });
        return const NarouLoginResult.failure('認証画面への転送回数が上限を超えました');
      }

      final challengePage = challengeResponse?.data ?? response.data ?? '';
      final pageUri = challengeResponse?.realUri ?? response.realUri;
      final pending = await _resolveMfaChallenge(
        challengePage,
        pageUri,
        cookies,
        narouid,
        rememberSession: rememberSession,
        generation: generation,
        operationId: operationId,
      );
      if (!_isCurrentAuthOperation(generation)) {
        _log(operationId, 'login.cancelled', <String, Object?>{
          'stage': 'challenge-resolution',
        });
        return _cancelledLoginResult;
      }
      if (pending == null) {
        _log(operationId, 'login.result', <String, Object?>{
          'outcome': 'failure',
          'reason': 'mfa-challenge-not-found',
        });
        return const NarouLoginResult.failure(
          'ログインに失敗しました。ID・パスワードと二段階認証の表示を確認してください。',
        );
      }
      _pendingMfa = pending;
      _log(operationId, 'login.result', <String, Object?>{
        'outcome': 'mfa-required',
        'challengeType': pending.usedEmail ? 'email' : 'totp-or-email',
        'codeFieldClass': _diagnosticCodeFieldClass(pending.codeField),
        ..._diagnosticCookieMetadata(pending.cookies),
      });
      return NarouLoginResult.mfaRequired(
        diagnosticsOperationId: operationId,
      );
    } on DioException catch (e) {
      if (!_isCurrentAuthOperation(generation)) return _cancelledLoginResult;
      _log(operationId, 'login.result', <String, Object?>{
        'outcome': 'failure',
        'reason': 'network-error',
        'errorType': e.type.name,
        'status': e.response?.statusCode,
      });
      debugPrint(
        '[NarouAuth] login: 通信失敗 '
        'type=${e.type} status=${e.response?.statusCode}',
      );
      return const NarouLoginResult.failure('ログイン通信に失敗しました');
    } on Object catch (e) {
      if (!_isCurrentAuthOperation(generation)) return _cancelledLoginResult;
      _log(operationId, 'login.result', <String, Object?>{
        'outcome': 'failure',
        'reason': 'processing-error',
        'errorType': e.runtimeType.toString(),
      });
      debugPrint('[NarouAuth] login: 処理失敗 type=${e.runtimeType}');
      return const NarouLoginResult.failure('ログイン処理に失敗しました');
    }
  }

  /// メールまたは認証アプリで受け取った確認コードを一度だけ送信する。
  Future<NarouLoginResult> verifyMfaCode(String code) async {
    final pending = _pendingMfa;
    final generation = _authOperationGeneration;
    if (pending == null) {
      final operationId = _diagnostics.createOperationId();
      _log(operationId, 'mfa.verify.rejected', <String, Object?>{
        'reason': 'no-pending-challenge',
      });
      return const NarouLoginResult.failure('認証コードを確認できません。最初からログインしてください。');
    }
    final operationId = pending.operationId;
    final normalizedCode = code.trim();
    if (!RegExp(r'^\d{1,32}$').hasMatch(normalizedCode)) {
      _log(operationId, 'mfa.verify.rejected', <String, Object?>{
        'reason': 'invalid-code-format',
      });
      return const NarouLoginResult.failure(
        '認証コードを半角数字で入力してください。',
        canRetryMfa: true,
      );
    }

    try {
      _log(operationId, 'mfa.verify.started', <String, Object?>{
        'challengeType': pending.usedEmail ? 'email' : 'totp-or-email',
        'codeFormatValid': true,
        ..._diagnosticCookieMetadata(pending.cookies),
      });
      final sessionCookiesBeforeVerification = Map<String, String>.of(
        pending.cookies,
      );
      final fields = Map<String, String>.of(pending.hiddenFields)
        ..[pending.codeField] = normalizedCode;
      var response = await _sendDiagnosticRequest(
        operationId: operationId,
        method: 'POST',
        requestUri: pending.action,
        cookies: pending.cookies,
        fieldNames: fields.keys,
        send: () => _dio.post<String>(
          pending.action.toString(),
          data: fields,
          options: _htmlOptions(
            headers: {
              'Referer': pending.pageUri.toString(),
              ...?_cookieHeaderMap(pending.cookies),
            },
          ),
        ),
      );
      if (!_isCurrentMfaChallenge(generation, pending)) {
        _log(operationId, 'mfa.verify.cancelled', <String, Object?>{
          'stage': 'code-response',
        });
        return _cancelledLoginResult;
      }
      mergeSetCookieHeaders(
        pending.cookies,
        response.headers.map['set-cookie'],
      );
      var redirect = _responseRedirect(response);
      var redirectedToBookmarkList =
          redirect != null && _isNarouBookmarkListUri(redirect);
      var redirectHops = 0;
      for (var redirects = 0; redirect != null && redirects < 5; redirects++) {
        redirectHops = redirects + 1;
        if (!_isNarouUri(redirect)) {
          _log(operationId, 'mfa.redirect.rejected', <String, Object?>{
            'hop': redirectHops,
            'targetRoute': _diagnosticRoute(redirect),
            'trustedTarget': false,
          });
          _pendingMfa = null;
          return const NarouLoginResult.failure(
            '認証先を安全に確認できませんでした。ログインをやり直してください。',
          );
        }
        _log(operationId, 'mfa.redirect.follow', <String, Object?>{
          'hop': redirectHops,
          'targetRoute': _diagnosticRoute(redirect),
          'trustedTarget': true,
        });
        response = await _sendDiagnosticRequest(
          operationId: operationId,
          method: 'GET',
          requestUri: redirect,
          cookies: pending.cookies,
          send: () => _dio.get<String>(
            redirect.toString(),
            options: _htmlOptions(
              headers: {
                ...?_cookieHeaderMap(pending.cookies),
              },
            ),
          ),
        );
        if (!_isCurrentMfaChallenge(generation, pending)) {
          _log(operationId, 'mfa.verify.cancelled', <String, Object?>{
            'stage': 'redirect-response',
          });
          return _cancelledLoginResult;
        }
        mergeSetCookieHeaders(
          pending.cookies,
          response.headers.map['set-cookie'],
        );
        redirect = _responseRedirect(response);
        if (redirect != null) {
          redirectedToBookmarkList = _isNarouBookmarkListUri(redirect);
        }
      }
      if (redirect != null) {
        _log(operationId, 'auth.decision', <String, Object?>{
          'accepted': false,
          'reason': 'redirect-limit',
          'redirectHops': redirectHops,
          'redirectLimit': 5,
        });
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
        usedEmail: pending.usedEmail,
        rememberSession: pending.rememberSession,
        operationId: operationId,
      );
      if (!_isCurrentMfaChallenge(generation, pending)) {
        _log(operationId, 'mfa.verify.cancelled', <String, Object?>{
          'stage': 'final-page-parse',
        });
        return _cancelledLoginResult;
      }
      final hasSessionCookies = _hasSessionCookies(pending.cookies);
      final sessionCookieChanged = _hasUpdatedSessionCookie(
        sessionCookiesBeforeVerification,
        pending.cookies,
      );
      final responseUsername = _extractUsername(response.data);
      if (refreshedChallenge != null) {
        _pendingMfa = refreshedChallenge;
        _log(operationId, 'mfa.verify.result', <String, Object?>{
          'outcome': 'retryable-failure',
          'reason': 'challenge-refreshed',
        });
        return const NarouLoginResult.failure(
          '認証コードを確認できませんでした。コードを確認して再入力してください。',
          canRetryMfa: true,
        );
      }

      final responseTrusted = _isNarouUri(response.realUri);
      final isAuthenticatedUserPage =
          _isNarouUserTopUri(response.realUri) && responseUsername != null;
      final isAuthenticatedBookmarkPage =
          _isNarouBookmarkListUri(response.realUri) &&
          _isAuthenticatedBookmarkListHtml(response.data);
      var username = isAuthenticatedUserPage ? responseUsername : null;
      if (username == null && isAuthenticatedBookmarkPage) {
        username = responseUsername;
      }
      final hasMfaSuccessSignal =
          redirectedToBookmarkList || sessionCookieChanged || username != null;
      final decisionReason = response.statusCode != 200
          ? 'unexpected-status'
          : !responseTrusted
          ? 'untrusted-origin'
          : !hasSessionCookies
          ? 'required-session-cookies-missing'
          : !hasMfaSuccessSignal
          ? 'mfa-success-signal-missing'
          : 'accepted';
      _log(operationId, 'mfa.final-page', <String, Object?>{
        'route': _diagnosticRoute(response.realUri),
        'status': response.statusCode,
        'responseBytes': _responseBytes(response.data),
        'usernameMarkerPresent': responseUsername != null,
        'loginFormPresent': _isNarouLoginPageHtml(response.data),
        'authenticatedBookmarkMarker': isAuthenticatedBookmarkPage,
        'redirectedToBookmarkList': redirectedToBookmarkList,
        'redirectHops': redirectHops,
        'sessionCookieChanged': sessionCookieChanged,
        ..._diagnosticCookieMetadata(pending.cookies),
      });
      _log(operationId, 'auth.decision', <String, Object?>{
        'accepted': decisionReason == 'accepted',
        'reason': decisionReason,
        'httpStatusOkay': response.statusCode == 200,
        'trustedOrigin': responseTrusted,
        'requiredSessionCookiesPresent': hasSessionCookies,
        'sessionCookieChanged': sessionCookieChanged,
        'redirectedToBookmarkList': redirectedToBookmarkList,
        'recognizedAuthenticatedPage': username != null,
      });
      if (response.statusCode != 200 ||
          !responseTrusted ||
          !hasSessionCookies ||
          !hasMfaSuccessSignal) {
        _pendingMfa = null;
        _log(operationId, 'mfa.verify.result', <String, Object?>{
          'outcome': 'failure',
          'reason': decisionReason,
        });
        return const NarouLoginResult.failure(
          '認証コードを確認できませんでした。ログインをやり直してください。',
        );
      }

      if (username == null) {
        String? bookmarkHtml;
        if (isAuthenticatedBookmarkPage) {
          bookmarkHtml = response.data;
        } else {
          try {
            bookmarkHtml = await _fetchAuthenticatedBookmarkList(
              pending.cookies,
              operationId: operationId,
            );
          } on DioException catch (error) {
            if (!_isCurrentMfaChallenge(generation, pending)) {
              return _cancelledLoginResult;
            }
            _pendingMfa = null;
            _log(
              operationId,
              'bookmark.session-check.failed',
              <String, Object?>{
                'errorType': error.type.name,
                'status': error.response?.statusCode,
              },
            );
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
          _log(operationId, 'bookmark.session-check.result', <String, Object?>{
            'authenticated': false,
            'reason': 'authenticated-bookmark-marker-missing',
          });
          return const NarouLoginResult.failure(
            '認証後のセッションを確認できませんでした。ログインをやり直してください。',
          );
        }
        username = _extractUsername(bookmarkHtml) ?? pending.narouid;
        _log(operationId, 'bookmark.session-check.result', <String, Object?>{
          'authenticated': true,
          'usernameMarkerPresent': _extractUsername(bookmarkHtml) != null,
          'bookmarkMarkerPresent':
              parser.parse(bookmarkHtml).querySelector('.p-up-bookmark-item') !=
              null,
        });
      }

      _pendingMfa = null;
      final result = await _finishLogin(
        pending.cookies,
        pending.narouid,
        username,
        generation: generation,
        shouldSuggestAuthenticatorApp: pending.usedEmail,
        rememberSession: pending.rememberSession,
        operationId: operationId,
      );
      _log(operationId, 'mfa.verify.result', <String, Object?>{
        'outcome': result.isSuccess ? 'success' : 'failure',
        'reason': result.isSuccess ? 'authenticated' : 'session-save-failed',
      });
      return result;
    } on DioException catch (e) {
      if (!_isCurrentMfaChallenge(generation, pending)) {
        return _cancelledLoginResult;
      }
      final statusCode = e.response?.statusCode;
      if (_isExpiredMfaStatusCode(statusCode)) {
        pending.cookies.clear();
        _pendingMfa = null;
        _log(operationId, 'mfa.verify.result', <String, Object?>{
          'outcome': 'expired',
          'reason': 'terminal-http-status',
          'status': statusCode,
          'errorType': e.type.name,
        });
        debugPrint('[NarouAuth] MFAチャレンジ失効 status=$statusCode');
        return const NarouLoginResult.failure(
          '二段階認証の期限が切れました。IDとパスワードを入力してログインし直してください。',
        );
      }
      _log(operationId, 'mfa.verify.result', <String, Object?>{
        'outcome': 'retryable-failure',
        'reason': 'network-error',
        'errorType': e.type.name,
        'status': statusCode,
      });
      debugPrint(
        '[NarouAuth] MFA通信失敗 type=${e.type} status=${e.response?.statusCode}',
      );
      return const NarouLoginResult.failure(
        '認証コードの送信に失敗しました',
        canRetryMfa: true,
      );
    } on Object catch (e) {
      if (!_isCurrentMfaChallenge(generation, pending)) {
        return _cancelledLoginResult;
      }
      _log(operationId, 'mfa.verify.result', <String, Object?>{
        'outcome': 'retryable-failure',
        'reason': 'processing-error',
        'errorType': e.runtimeType.toString(),
      });
      debugPrint('[NarouAuth] MFA処理失敗 type=${e.runtimeType}');
      return const NarouLoginResult.failure(
        '認証コードの処理に失敗しました',
        canRetryMfa: true,
      );
    }
  }

  /// 保存済みのセッションが有効か確認する。
  ///
  /// ブックマーク一覧ページへアクセスし、200が返れば有効と判断する。
  /// 302リダイレクト（ログインページへ転送）が返れば無効と判断する。
  Future<bool> isSessionValid() async {
    final cookieHeader = await authRepository.buildCookieHeader();
    if (cookieHeader == null) return false;

    return await validateSession(cookieHeader) == NarouSessionValidity.valid;
  }

  /// 指定したセッションCookieの有効性を確認する。
  ///
  /// 401、ログイン画面への転送、ログインフォームが確認された場合に
  /// [NarouSessionValidity.invalid]を返し、それ以外の異常は確認不能として扱う。
  Future<NarouSessionValidity> validateSession(String cookieHeader) async {
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
      final statusCode = response.statusCode;
      if (statusCode != null && statusCode >= 300 && statusCode < 400) {
        final redirect = _responseRedirect(response);
        return redirect != null && _isNarouLoginUri(redirect)
            ? NarouSessionValidity.invalid
            : NarouSessionValidity.unavailable;
      }
      if (statusCode == 401) return NarouSessionValidity.invalid;
      final data = response.data;
      if (statusCode != 200 || !_isNarouBookmarkListUri(response.realUri)) {
        return NarouSessionValidity.unavailable;
      }
      if (_isNarouLoginPageHtml(data)) return NarouSessionValidity.invalid;
      if (!_isAuthenticatedBookmarkListHtml(data)) {
        return NarouSessionValidity.unavailable;
      }
      await authRepository.updateSessionCookieHeaders(
        response.headers.map['set-cookie'],
        expectedCookieHeader: cookieHeader,
      );
      return NarouSessionValidity.valid;
    } on Exception {
      return NarouSessionValidity.unavailable;
    }
  }

  /// 保留中のMFAチャレンジと仮Cookieを破棄する。
  void cancelMfaChallenge() {
    _discardMfaChallenge(reason: 'user-cancelled');
  }

  void _discardMfaChallenge({required String reason}) {
    final operationId = _pendingMfa?.operationId;
    if (operationId != null) {
      _log(operationId, 'mfa.challenge.discarded', <String, Object?>{
        'reason': reason,
      });
    }
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
    required String operationId,
    bool shouldSuggestAuthenticatorApp = false,
    bool rememberSession = true,
  }) async {
    _log(operationId, 'session.persist.started', <String, Object?>{
      'rememberSession': rememberSession,
      ..._diagnosticCookieMetadata(cookies),
    });
    var cancelled = false;
    var cleanedAfterCancellation = false;
    try {
      await _serializeSessionMutation(() async {
        if (!_isCurrentAuthOperation(generation)) {
          cancelled = true;
          return;
        }

        await authRepository.saveSession(
          narouid: narouid,
          username: username,
          ks2: cookies['ks2']!,
          ses: cookies['ses']!,
          userl: cookies['userl']!,
          rememberSession: rememberSession,
        );
        if (!_isCurrentAuthOperation(generation)) {
          cancelled = true;
          cleanedAfterCancellation = true;
          await authRepository.clearAll();
        }
      });
    } on Object catch (error) {
      _log(operationId, 'session.persist.failed', <String, Object?>{
        'errorType': error.runtimeType.toString(),
      });
      rethrow;
    }

    if (cancelled || !_isCurrentAuthOperation(generation)) {
      if (!cleanedAfterCancellation) {
        await _serializeSessionMutation(authRepository.clearAll);
      }
      _log(operationId, 'session.persist.cancelled');
      return _cancelledLoginResult;
    }
    _log(operationId, 'session.persisted', <String, Object?>{
      'rememberSession': rememberSession,
      'requiredSessionCookiesPresent': _hasSessionCookies(cookies),
    });
    return NarouLoginResult.success(
      username: username,
      shouldSuggestAuthenticatorApp: shouldSuggestAuthenticatorApp,
      diagnosticsOperationId: operationId,
    );
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
    final hasLoginForm = _hasNarouLoginForm(document);
    final hasBookmarkPage =
        document.querySelector('.p-up-bookmark-item') != null ||
        _extractUsername(html) != null;
    return !hasLoginForm && hasBookmarkPage;
  }

  bool _isNarouLoginPageHtml(String? html) {
    if (html == null || html.isEmpty) return false;
    return _hasNarouLoginForm(parser.parse(html));
  }

  bool _hasNarouLoginForm(Document document) =>
      document.querySelector('form[action*="/login/login/"]') != null;

  Future<String?> _fetchAuthenticatedBookmarkList(
    Map<String, String> cookies, {
    required String operationId,
  }) async {
    final response = await _sendDiagnosticRequest(
      operationId: operationId,
      method: 'GET',
      requestUri: Uri.parse(_bookmarkListUrl),
      cookies: cookies,
      send: () => _dio.get<String>(
        _bookmarkListUrl,
        options: _htmlOptions(headers: {...?_cookieHeaderMap(cookies)}),
      ),
    );
    if (response.statusCode != 200 ||
        !_isNarouBookmarkListUri(response.realUri)) {
      return null;
    }
    mergeSetCookieHeaders(cookies, response.headers.map['set-cookie']);
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

  Uri? _responseRedirect(Response<dynamic> response) {
    final location = response.headers.value('location');
    if (location == null) return null;
    return response.realUri.resolve(location);
  }

  bool _isNarouUri(Uri uri) => isTrustedNarouUri(uri);

  bool _isNarouBookmarkListUri(Uri uri) =>
      _isNarouUri(uri) &&
      uri.path == Uri.parse(_bookmarkListUrl).path &&
      uri.query.isEmpty &&
      uri.fragment.isEmpty;

  bool _isNarouUserTopUri(Uri uri) =>
      _isNarouUri(uri) &&
      uri.path == '/user/top/' &&
      uri.query.isEmpty &&
      uri.fragment.isEmpty;

  bool _isExpiredMfaStatusCode(int? statusCode) =>
      statusCode == 401 ||
      statusCode == 403 ||
      statusCode == 404 ||
      statusCode == 410 ||
      statusCode == 419;

  bool _isNarouLoginUri(Uri uri) => isNarouLoginUri(uri);

  bool _isNarouLoginAction(Uri uri) =>
      _isNarouUri(uri) && uri.path == Uri.parse(_loginUrl).path;

  bool _isNarouMfaAction(Uri uri) =>
      _isNarouUri(uri) &&
      (uri.path.startsWith('/login/auth_code/verify/') ||
          uri.path.startsWith('/user2stepauth/totpauth/') ||
          uri.path.startsWith('/user2stepauth/emailauth/'));

  bool _isNarouTotpPage(Uri uri) =>
      _isNarouUri(uri) &&
      uri.path.startsWith('/user2stepauth/totpinput/') &&
      uri.query.isEmpty &&
      uri.fragment.isEmpty;

  bool _isNarouEmailChoiceAction(Uri uri) =>
      _isNarouUri(uri) &&
      uri.path.startsWith('/user2stepauth/sendemail/') &&
      uri.query.isEmpty &&
      uri.fragment.isEmpty;

  bool _hasSessionCookies(Map<String, String> cookies) =>
      cookies['ks2']?.isNotEmpty == true &&
      cookies['ses']?.isNotEmpty == true &&
      cookies['userl']?.isNotEmpty == true;

  bool _hasUpdatedSessionCookie(
    Map<String, String> previous,
    Map<String, String> current,
  ) => const <String>['ks2', 'ses', 'userl'].any(
    (name) =>
        current[name]?.isNotEmpty == true && current[name] != previous[name],
  );

  _PendingNarouMfa? _parseMfaChallenge(
    String html,
    Uri pageUri,
    Map<String, String> cookies,
    String narouid, {
    required String operationId,
    bool usedEmail = false,
    bool rememberSession = true,
  }) {
    _log(operationId, 'mfa.challenge.parse.started', <String, Object?>{
      'pageRoute': _diagnosticRoute(pageUri),
      'trustedPage': _isNarouUri(pageUri),
      'responseBytes': _responseBytes(html),
    });
    if (!_isNarouUri(pageUri)) {
      _log(operationId, 'mfa.challenge.parsed', <String, Object?>{
        'result': 'rejected',
        'reason': 'untrusted-page',
      });
      return null;
    }
    final document = parser.parse(html);
    final pageText = document.body?.text.toLowerCase() ?? '';
    final hasCodePrompt =
        pageText.contains('認証コード') ||
        pageText.contains('二段階認証') ||
        pageText.contains('2段階認証') ||
        pageText.contains('ワンタイム');
    if (!hasCodePrompt) {
      _log(operationId, 'mfa.challenge.parsed', <String, Object?>{
        'result': 'missing',
        'reason': 'code-prompt-missing',
        'formCount': document.querySelectorAll('form').length,
      });
      return null;
    }

    final forms = document.querySelectorAll('form');
    Element? form;
    for (final candidate in forms) {
      if (_codeInput(candidate) != null) {
        form = candidate;
        break;
      }
    }
    if (form == null) {
      _log(operationId, 'mfa.challenge.parsed', <String, Object?>{
        'result': 'missing',
        'reason': 'code-form-missing',
        'formCount': forms.length,
      });
      return null;
    }
    final codeInput = _codeInput(form)!;
    final codeField = codeInput.attributes['name'];
    if (codeField == null || codeField.isEmpty) {
      _log(operationId, 'mfa.challenge.parsed', <String, Object?>{
        'result': 'rejected',
        'reason': 'code-field-name-missing',
      });
      return null;
    }
    final action = _formAction(form, pageUri, fallback: pageUri);
    if (!_isNarouMfaAction(action)) {
      _log(operationId, 'mfa.challenge.parsed', <String, Object?>{
        'result': 'rejected',
        'reason': 'untrusted-action',
        'actionRoute': _diagnosticRoute(action),
      });
      return null;
    }
    final hasTotpOption = document.querySelectorAll('a[href]').any((anchor) {
      final href = anchor.attributes['href'];
      return href != null && _isNarouTotpPage(pageUri.resolve(href));
    });
    final isTotpChallenge =
        _isNarouTotpPage(pageUri) ||
        action.path.startsWith('/user2stepauth/totpauth/') ||
        codeField.toLowerCase().contains('totp');
    final emailCodeChallenge =
        !isTotpChallenge &&
        (pageUri.path.startsWith('/user2stepauth/emailinput/') ||
            action.path.startsWith('/user2stepauth/emailauth/') ||
            codeField.toLowerCase().contains('email') ||
            pageText.contains('メール認証') ||
            pageText.contains('登録メールに送信'));
    final emailIsOnlyOption = emailCodeChallenge && !hasTotpOption;
    final shouldSuggestAuthenticatorApp =
        !isTotpChallenge && (usedEmail || emailIsOnlyOption);
    _log(operationId, 'mfa.challenge.parsed', <String, Object?>{
      'result': 'found',
      'pageRoute': _diagnosticRoute(pageUri),
      'actionRoute': _diagnosticRoute(action),
      'codeFieldClass': _diagnosticCodeFieldClass(codeField),
      'hiddenFieldNames': _safeDiagnosticNames(_hiddenFields(form).keys),
      'hasTotpOption': hasTotpOption,
      'challengeType': isTotpChallenge ? 'totp' : 'email-or-other',
      'shouldSuggestAuthenticatorApp': shouldSuggestAuthenticatorApp,
    });
    return _PendingNarouMfa(
      action: action,
      pageUri: pageUri,
      codeField: codeField,
      hiddenFields: _hiddenFields(form),
      cookies: Map<String, String>.of(cookies),
      narouid: narouid,
      usedEmail: shouldSuggestAuthenticatorApp,
      rememberSession: rememberSession,
      operationId: operationId,
    );
  }

  Future<_PendingNarouMfa?> _resolveMfaChallenge(
    String html,
    Uri pageUri,
    Map<String, String> cookies,
    String narouid, {
    required bool rememberSession,
    required int generation,
    required String operationId,
  }) async {
    if (!_isNarouUri(pageUri)) {
      _log(operationId, 'mfa.challenge.resolve.rejected', <String, Object?>{
        'reason': 'untrusted-page',
        'pageRoute': _diagnosticRoute(pageUri),
      });
      return null;
    }
    final directChallenge = _parseMfaChallenge(
      html,
      pageUri,
      cookies,
      narouid,
      rememberSession: rememberSession,
      operationId: operationId,
    );
    if (directChallenge != null) return directChallenge;

    final document = parser.parse(html);
    Uri? totpUri;
    for (final anchor in document.querySelectorAll('a[href]')) {
      final href = anchor.attributes['href'];
      if (href == null || href.isEmpty) continue;
      final target = pageUri.resolve(href);
      if (_isNarouTotpPage(target)) {
        totpUri = target;
        break;
      }
    }
    if (totpUri != null) {
      return _fetchMfaCodePage(
        totpUri,
        cookies,
        narouid,
        usedEmail: false,
        rememberSession: rememberSession,
        generation: generation,
        operationId: operationId,
      );
    }

    for (final form in document.querySelectorAll('form')) {
      final action = _formAction(form, pageUri, fallback: pageUri);
      if (!_isNarouEmailChoiceAction(action) ||
          (form.attributes['method'] ?? 'get').toLowerCase() != 'post') {
        continue;
      }
      final fields = _emailChoiceFields(form);
      if (fields == null) {
        _log(operationId, 'mfa.email-choice.rejected', <String, Object?>{
          'reason': 'choice-fields-missing',
        });
        return null;
      }
      final response = await _sendDiagnosticRequest(
        operationId: operationId,
        method: 'POST',
        requestUri: action,
        cookies: cookies,
        fieldNames: fields.keys,
        send: () => _dio.post<String>(
          action.toString(),
          data: fields,
          options: _htmlOptions(
            headers: {
              'Referer': pageUri.toString(),
              ...?_cookieHeaderMap(cookies),
            },
          ),
        ),
      );
      if (!_isCurrentAuthOperation(generation)) return null;
      mergeSetCookieHeaders(cookies, response.headers.map['set-cookie']);
      final redirect = _responseRedirect(response);
      if (redirect != null) {
        if (!_isNarouUri(redirect)) {
          _log(operationId, 'mfa.email-choice.rejected', <String, Object?>{
            'reason': 'untrusted-redirect',
            'targetRoute': _diagnosticRoute(redirect),
          });
          return null;
        }
        return _fetchMfaCodePage(
          redirect,
          cookies,
          narouid,
          usedEmail: true,
          rememberSession: rememberSession,
          generation: generation,
          operationId: operationId,
        );
      }
      return _parseMfaChallenge(
        response.data ?? '',
        response.realUri,
        cookies,
        narouid,
        usedEmail: true,
        rememberSession: rememberSession,
        operationId: operationId,
      );
    }
    return null;
  }

  Future<_PendingNarouMfa?> _fetchMfaCodePage(
    Uri startUri,
    Map<String, String> cookies,
    String narouid, {
    required bool usedEmail,
    required bool rememberSession,
    required int generation,
    required String operationId,
  }) async {
    var current = startUri;
    for (var redirects = 0; redirects <= 5; redirects++) {
      if (!_isNarouUri(current)) {
        _log(operationId, 'mfa.code-page.rejected', <String, Object?>{
          'reason': 'untrusted-target',
          'route': _diagnosticRoute(current),
        });
        return null;
      }
      final response = await _sendDiagnosticRequest(
        operationId: operationId,
        method: 'GET',
        requestUri: current,
        cookies: cookies,
        send: () => _dio.get<String>(
          current.toString(),
          options: _htmlOptions(headers: {...?_cookieHeaderMap(cookies)}),
        ),
      );
      if (!_isCurrentAuthOperation(generation)) return null;
      if (!_isNarouUri(response.realUri)) {
        _log(operationId, 'mfa.code-page.rejected', <String, Object?>{
          'reason': 'untrusted-response',
          'route': _diagnosticRoute(response.realUri),
        });
        return null;
      }
      mergeSetCookieHeaders(cookies, response.headers.map['set-cookie']);
      final redirect = _responseRedirect(response);
      if (redirect == null) {
        return _parseMfaChallenge(
          response.data ?? '',
          response.realUri,
          cookies,
          narouid,
          usedEmail: usedEmail,
          rememberSession: rememberSession,
          operationId: operationId,
        );
      }
      if (!_isNarouUri(redirect) || redirects == 5) {
        _log(operationId, 'mfa.code-page.rejected', <String, Object?>{
          'reason': _isNarouUri(redirect)
              ? 'redirect-limit'
              : 'untrusted-redirect',
          'route': _diagnosticRoute(redirect),
          'redirectHops': redirects + 1,
        });
        return null;
      }
      current = redirect;
    }
    return null;
  }

  Map<String, String>? _emailChoiceFields(Element form) {
    final radios = form.querySelectorAll('input[type="radio"][name]');
    if (radios.isEmpty) return null;
    final chosen = radios.firstWhere(
      (radio) => radio.attributes.containsKey('checked'),
      orElse: () => radios.first,
    );
    final name = chosen.attributes['name'];
    final value = chosen.attributes['value'];
    if (name == null || name.isEmpty || value == null || value.isEmpty) {
      return null;
    }
    return _hiddenFields(form)..[name] = value;
  }

  Map<String, String> _persistentLoginFields(
    Element form,
    bool rememberSession,
  ) {
    if (!rememberSession) return const {};
    final fields = <String, String>{};
    for (final input in form.querySelectorAll('input[type="checkbox"][name]')) {
      final name = input.attributes['name'];
      if (name == null || name.isEmpty) continue;
      final labelText = input.parent?.text ?? '';
      final searchable = '${name.toLowerCase()} ${labelText.toLowerCase()}';
      if (!searchable.contains('auto') &&
          !searchable.contains('remember') &&
          !searchable.contains('次回から自動的にログイン')) {
        continue;
      }
      fields[name] = input.attributes['value'] ?? 'on';
    }
    return fields;
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
        'security[_-]?code|confirmation[_-]?code|totp[_-]?code|'
        'email[_-]?code)'
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
    required this.operationId,
    this.usedEmail = false,
    this.rememberSession = true,
  });

  final Uri action;
  final Uri pageUri;
  final String codeField;
  final Map<String, String> hiddenFields;
  final Map<String, String> cookies;
  final String narouid;
  final String operationId;
  final bool usedEmail;
  final bool rememberSession;
}

/// ログイン処理の結果を表すクラス。
class NarouLoginResult {
  /// ログイン成功。
  const NarouLoginResult.success({
    required this.username,
    this.shouldSuggestAuthenticatorApp = false,
    this.diagnosticsOperationId,
  }) : isSuccess = true,
       requiresMfa = false,
       canRetryMfa = false,
       error = null;

  /// 二段階認証コードの入力待ち。
  const NarouLoginResult.mfaRequired({this.diagnosticsOperationId})
    : isSuccess = false,
      requiresMfa = true,
      canRetryMfa = true,
      username = null,
      shouldSuggestAuthenticatorApp = false,
      error = null;

  /// ログイン失敗。
  const NarouLoginResult.failure(
    String this.error, {
    this.canRetryMfa = false,
  }) : isSuccess = false,
       requiresMfa = false,
       username = null,
       shouldSuggestAuthenticatorApp = false,
       diagnosticsOperationId = null;

  /// 成功したか否か。
  final bool isSuccess;

  /// 二段階認証コードの入力が必要か。
  final bool requiresMfa;

  /// 保留中の二段階認証チャレンジで再試行できるか。
  final bool canRetryMfa;

  /// ログイン成功時のユーザー名。
  final String? username;

  /// メール認証でログインし、認証アプリの設定案内を表示する必要があるか。
  final bool shouldSuggestAuthenticatorApp;

  /// 認証イベントを相関させる開発用操作ID。
  final String? diagnosticsOperationId;

  /// ログイン失敗時のエラーメッセージ。
  final String? error;
}
