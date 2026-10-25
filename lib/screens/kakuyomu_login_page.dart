import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:novelty/providers/auth_provider.dart';
import 'package:novelty/services/debug_webview_http_trace.dart';
import 'package:novelty/services/kakuyomu_auth_service.dart';
import 'package:novelty/services/kakuyomu_login_check_queue.dart';
import 'package:novelty/services/kakuyomu_login_error_message.dart';
import 'package:novelty/services/kakuyomu_web_cookie_service.dart';
import 'package:novelty/services/narou_auth_diagnostics.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:novelty/utils/kakuyomu_uri.dart';
import 'package:novelty/utils/kakuyomu_webview_support.dart';

const _kakuyomuLoginUrl = 'https://kakuyomu.jp/auth/login';
const _kakuyomuLoginAttemptHandler = 'noveltyKakuyomuLoginAttempt';
const _kakuyomuLoginAttemptScript = r'''
(() => {
  if (window.__noveltyKakuyomuLoginAttemptInstalled) return;
  window.__noveltyKakuyomuLoginAttemptInstalled = true;
  document.addEventListener('submit', (event) => {
    const form = event.target;
    if (!(form instanceof HTMLFormElement)) return;
    try {
      const action = new URL(form.action || window.location.href, window.location.href);
      const loginPath = /\/(auth|login)(\/|$)/i;
      if (action.protocol !== 'https:' || action.hostname !== 'kakuyomu.jp' ||
          !loginPath.test(action.pathname) && !loginPath.test(window.location.pathname)) return;
      const bridge = window.flutter_inappwebview;
      if (bridge && typeof bridge.callHandler === 'function') {
        const pending = bridge.callHandler('noveltyKakuyomuLoginAttempt');
        if (pending && typeof pending.catch === 'function') pending.catch(() => {});
      }
    } catch (_) {}
  }, true);
})();
''';

/// カクヨム公式ログイン画面を表示し、ログイン済み Cookie を保存する画面。
class KakuyomuLoginPage extends ConsumerStatefulWidget {
  /// コンストラクタ。
  const KakuyomuLoginPage({super.key});

  @override
  ConsumerState<KakuyomuLoginPage> createState() => _KakuyomuLoginPageState();
}

class _KakuyomuLoginPageState extends ConsumerState<KakuyomuLoginPage> {
  bool _isPreparing = true;
  bool _isCheckingLogin = false;
  bool _isCompleted = false;
  bool _loginAttempted = false;
  String? _errorMessage;
  late final String _loginOperationId;
  late final DebugWebViewHttpTrace _webViewHttpTrace;
  final KakuyomuLoginCheckQueue _loginCheckQueue = KakuyomuLoginCheckQueue();
  int _loginCheckCount = 0;

  @override
  void initState() {
    super.initState();
    final diagnostics = ref.read(appDiagnosticsLoggerProvider);
    _loginOperationId = diagnostics.createOperationId();
    _webViewHttpTrace = DebugWebViewHttpTrace(
      diagnostics: diagnostics,
      operationId: _loginOperationId,
      source: NovelSource.kakuyomu,
    );
    if (isKakuyomuWebViewSupported) {
      unawaited(_prepareSession());
    } else {
      _isPreparing = false;
    }
  }

  Future<void> _prepareSession() async {
    try {
      await ref.read(kakuyomuWebCookieServiceProvider).restoreToWebView();
    } on Exception {
      // WebView側Cookieを復元できなくても、新規ログインは続行できる。
    }

    if (!mounted) return;
    setState(() => _isPreparing = false);
  }

  Future<void> _tryCompleteLogin(
    WebUri? currentUrl, {
    required String trigger,
  }) {
    final diagnostics = ref.read(appDiagnosticsLoggerProvider);
    final currentPath = _diagnosticPagePath(currentUrl);
    final loginAttempted = _loginAttempted;
    final resetLoginAttempt = shouldResetKakuyomuLoginAttempt(currentPath);
    if (resetLoginAttempt) _loginAttempted = false;
    diagnostics.record(_loginOperationId, 'kakuyomu.login.navigation', {
      'trigger': trigger,
      'pagePath': currentPath,
      'loginAttempted': loginAttempted,
      'loginAttemptReset': resetLoginAttempt,
    });
    if (!shouldCheckKakuyomuLoginAfterNavigation(
      loginAttempted: loginAttempted,
      pagePath: currentPath,
    )) {
      return Future<void>.value();
    }
    return _loginCheckQueue.request(
      () => _checkLoginAfterNavigation(
        currentPath: currentPath,
        trigger: trigger,
        diagnostics: diagnostics,
      ),
    );
  }

  Future<bool> _checkLoginAfterNavigation({
    required String currentPath,
    required String trigger,
    required AppDiagnosticsLogger diagnostics,
  }) async {
    if (!mounted || _isCompleted) return _isCompleted;
    final attempt = ++_loginCheckCount;
    try {
      setState(() {
        _isCheckingLogin = true;
        _errorMessage = null;
      });

      diagnostics.record(_loginOperationId, 'kakuyomu.login.check.started', {
        'attempt': attempt,
        'trigger': trigger,
        'pagePath': currentPath,
      });

      final cookies = await ref
          .read(kakuyomuWebCookieServiceProvider)
          .captureFromWebView();
      diagnostics.record(
        _loginOperationId,
        'kakuyomu.login.cookies.captured',
        {
          'attempt': attempt,
          'count': cookies.length,
          'names': cookies.map((cookie) => cookie.name).toSet().toList()
            ..sort(),
          'domains': cookies.map((cookie) => cookie.domain).toSet().toList()
            ..sort(),
        },
      );
      if (cookies.isEmpty) {
        if (mounted && shouldShowKakuyomuLoginCheckError(currentPath)) {
          setState(() {
            _errorMessage = 'カクヨムのログインCookieを取得できませんでした。';
          });
        }
        return false;
      }

      final authService = ref.read(kakuyomuAuthServiceProvider);
      final sessionStatus = await authService.validateSessionStatus();
      diagnostics.record(
        _loginOperationId,
        'kakuyomu.login.session_check.completed',
        {
          'attempt': attempt,
          'status': sessionStatus.name,
        },
      );
      if (sessionStatus != KakuyomuSessionValidity.valid) {
        if (mounted && shouldShowKakuyomuLoginCheckError(currentPath)) {
          setState(() {
            _errorMessage = sessionStatus == KakuyomuSessionValidity.unavailable
                ? 'カクヨムのログイン状態を確認できませんでした。通信状態を確認してください。'
                : 'Cookieは取得しましたが、カクヨムのログインを確認できません。';
          });
        }
        return false;
      }

      if (!mounted) return false;
      _isCompleted = true;
      ref.invalidate(accountAuthStateProvider(NovelSource.kakuyomu));

      Navigator.of(context).pop(true);
      return true;
    } on Exception catch (error, stackTrace) {
      final keychainErrorMessage = kakuyomuLoginErrorMessage(error);
      diagnostics
        ..record(_loginOperationId, 'kakuyomu.login.check.failed', {
          'attempt': attempt,
          'pagePath': currentPath,
          'errorType': error.runtimeType.toString(),
        })
        ..recordTrace(
          _loginOperationId,
          'kakuyomu.login.check.failed.trace',
          {
            'attempt': attempt,
            'pagePath': currentPath,
            'error': error.toString(),
            'stackTrace': stackTrace.toString(),
          },
        );
      if (mounted &&
          (keychainErrorMessage != null ||
              shouldShowKakuyomuLoginCheckError(currentPath))) {
        setState(() {
          _errorMessage =
              keychainErrorMessage ?? 'ログイン状態を確認できませんでした。もう一度お試しください。';
        });
      }
      return false;
    } finally {
      if (mounted && !_isCompleted) {
        setState(() => _isCheckingLogin = false);
      }
    }
  }

  String _diagnosticPagePath(WebUri? currentUrl) {
    if (currentUrl == null) return 'unknown';
    final uri = Uri.tryParse(currentUrl.toString());
    if (uri == null || !isTrustedKakuyomuUri(uri)) return 'external';
    return uri.path;
  }

  @override
  Widget build(BuildContext context) {
    if (!isKakuyomuWebViewSupported) {
      return Scaffold(
        appBar: AppBar(title: const Text('カクヨムアカウント')),
        body: const Center(
          child: Text('カクヨムアカウント連携は現在このOSでは利用できません。'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('カクヨムにログイン')),
      body: Column(
        children: [
          if (_errorMessage != null)
            MaterialBanner(
              content: Text(_errorMessage!),
              actions: [
                TextButton(
                  onPressed: () => setState(() => _errorMessage = null),
                  child: const Text('閉じる'),
                ),
              ],
            ),
          if (_isCheckingLogin) const LinearProgressIndicator(),
          Expanded(
            child: _isPreparing
                ? const Center(child: CircularProgressIndicator())
                : InAppWebView(
                    initialUrlRequest: URLRequest(
                      url: WebUri(_kakuyomuLoginUrl),
                    ),
                    initialSettings: InAppWebViewSettings(
                      useOnNavigationResponse:
                          _webViewHttpTrace.navigationResponseTracingEnabled,
                    ),
                    initialUserScripts: UnmodifiableListView<UserScript>([
                      UserScript(
                        source: _kakuyomuLoginAttemptScript,
                        injectionTime:
                            UserScriptInjectionTime.AT_DOCUMENT_START,
                      ),
                      ..._webViewHttpTrace.initialUserScripts,
                    ]),
                    onWebViewCreated: (controller) {
                      controller.addJavaScriptHandler(
                        handlerName: _kakuyomuLoginAttemptHandler,
                        callback: (_) {
                          _loginAttempted = true;
                          return null;
                        },
                      );
                      _webViewHttpTrace.registerHandler(controller);
                    },
                    onNavigationResponse:
                        _webViewHttpTrace.navigationResponseTracingEnabled
                        ? (_, response) async => _webViewHttpTrace
                              .recordNavigationResponse(response)
                        : null,
                    onLoadStop: (controller, url) async {
                      await _webViewHttpTrace.recordRenderedDocument(
                        controller,
                        url,
                      );
                      await _tryCompleteLogin(url, trigger: 'loadStop');
                    },
                    onUpdateVisitedHistory:
                        (controller, url, androidIsReload) async {
                          await _tryCompleteLogin(
                            url,
                            trigger: 'visitedHistory',
                          );
                        },
                  ),
          ),
        ],
      ),
    );
  }
}
