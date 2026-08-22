import 'dart:async';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:novelty/repositories/kakuyomu_session_repository.dart';
import 'package:novelty/services/kakuyomu_auth_service.dart';
import 'package:novelty/services/kakuyomu_web_cookie_service.dart';
import 'package:novelty/sites/account_sync_adapter.dart';
import 'package:novelty/utils/kakuyomu_webview_support.dart';

const _workLoadTimeout = Duration(seconds: 20);

/// カクヨム作品のフォロー状態を変更する処理。
typedef KakuyomuWorkFollowOperator =
    Future<AccountSyncOutcome> Function(String workId, bool shouldFollow);

/// カクヨム公式作品ページを使ってフォロー・解除を行うサービス。
///
/// 非公開APIのURL・CSRF仕様を推測せず、ログイン済みWebView上で
/// 公式UIを操作し、再読み込み後のボタン状態で結果を確認する。
class KakuyomuWorkFollowService {
  /// コンストラクタ。
  KakuyomuWorkFollowService({
    required KakuyomuSessionRepository sessionRepository,
    KakuyomuAuthService? authService,
  }) : _sessionRepository = sessionRepository,
       _authService = authService ??
           KakuyomuAuthService(sessionRepository: sessionRepository);

  final KakuyomuSessionRepository _sessionRepository;
  final KakuyomuAuthService _authService;

  /// [workId] の作品をフォロー、またはフォロー解除する。
  Future<AccountSyncOutcome> setFollowing(
    String workId, {
    required bool shouldFollow,
  }) async {
    if (!isKakuyomuWebViewSupported) {
      return AccountSyncOutcome.failed;
    }

    if (!await _authService.isSessionValid()) {
      return AccountSyncOutcome.notLoggedIn;
    }

    final webCookieService = KakuyomuWebCookieService(
      sessionRepository: _sessionRepository,
    );
    await webCookieService.restoreToWebView();

    final initialLoad = Completer<WebUri?>();
    var loadCompleter = initialLoad;
    final workUrl = WebUri('https://kakuyomu.jp/works/$workId');

    final headless = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: workUrl),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        thirdPartyCookiesEnabled: true,
      ),
      onLoadStop: (controller, url) async {
        if (!loadCompleter.isCompleted) {
          loadCompleter.complete(url);
        }
      },
    );

    try {
      await headless.run();
      final firstUrl = await initialLoad.future.timeout(_workLoadTimeout);
      if (_isLoginUrl(firstUrl)) return AccountSyncOutcome.notLoggedIn;

      final controller = headless.webViewController;
      if (controller == null) return AccountSyncOutcome.failed;

      final currentState = await _readFollowState(controller);
      if (_matchesDesiredState(currentState, shouldFollow)) {
        return AccountSyncOutcome.success;
      }
      if (currentState == _FollowState.missing) {
        return AccountSyncOutcome.failed;
      }

      final clicked = await _clickWorkFollowButton(
        controller,
        shouldFollow: shouldFollow,
      );
      if (!clicked) return AccountSyncOutcome.failed;

      // 公式UI側の非同期処理が完了する時間を確保してから再読込し、
      // 画面上の状態ではなくサーバー反映後の状態を確認する。
      await Future<void>.delayed(const Duration(milliseconds: 800));
      loadCompleter = Completer<WebUri?>();
      await controller.reload();
      final reloadedUrl = await loadCompleter.future.timeout(_workLoadTimeout);
      if (_isLoginUrl(reloadedUrl)) return AccountSyncOutcome.notLoggedIn;

      final verifiedState = await _readFollowState(controller);
      if (!_matchesDesiredState(verifiedState, shouldFollow)) {
        return AccountSyncOutcome.failed;
      }

      // 操作中にセッションCookieが更新された場合も永続側へ反映する。
      await webCookieService.captureFromWebView();
      return AccountSyncOutcome.success;
    } on TimeoutException {
      return AccountSyncOutcome.failed;
    } on Exception {
      return AccountSyncOutcome.failed;
    } finally {
      await headless.dispose();
    }
  }

  bool _isLoginUrl(WebUri? url) {
    if (url == null) return false;
    final uri = Uri.tryParse(url.toString());
    if (uri == null) return false;
    return uri.path.startsWith('/auth/login') || uri.path == '/login';
  }

  bool _matchesDesiredState(_FollowState state, bool shouldFollow) {
    return shouldFollow
        ? state == _FollowState.following
        : state == _FollowState.notFollowing;
  }

  Future<_FollowState> _readFollowState(
    InAppWebViewController controller,
  ) async {
    final result = await controller.evaluateJavascript(
      source: _buildFollowButtonScript(click: false),
    );
    return _parseFollowState(result);
  }

  Future<bool> _clickWorkFollowButton(
    InAppWebViewController controller, {
    required bool shouldFollow,
  }) async {
    final result = await controller.evaluateJavascript(
      source: _buildFollowButtonScript(
        click: true,
        shouldFollow: shouldFollow,
      ),
    );
    return _normalizeJavascriptResult(result) == 'clicked';
  }

  String _buildFollowButtonScript({
    required bool click,
    bool? shouldFollow,
  }) {
    final desiredCurrentText = shouldFollow == true ? 'フォロー' : 'フォロー中';
    final action = click
        ? '''
      if (text !== '$desiredCurrentText') return 'state_mismatch';
      button.click();
      return 'clicked';
    '''
        : '''
      return text === 'フォロー中'
        ? 'following'
        : text === 'フォロー'
          ? 'not_following'
          : 'missing';
    ''';

    return '''
(() => {
  const normalize = (element) =>
    (element?.textContent ?? '').replace(/\\s+/g, '').trim();
  const title = document.querySelector('h1');
  if (!title) return 'missing';

  const candidates = Array.from(
    document.querySelectorAll('button, [role="button"]'),
  ).filter((element) => {
    const text = normalize(element);
    return text === 'フォロー' || text === 'フォロー中';
  });
  if (candidates.length === 0) return 'missing';

  const titleAncestors = new Map();
  let node = title;
  let distance = 0;
  while (node) {
    titleAncestors.set(node, distance++);
    node = node.parentElement;
  }

  const distanceFromTitle = (element) => {
    let current = element;
    let elementDistance = 0;
    while (current) {
      if (titleAncestors.has(current)) {
        return elementDistance + titleAncestors.get(current);
      }
      current = current.parentElement;
      elementDistance++;
    }
    return Number.MAX_SAFE_INTEGER;
  };

  candidates.sort((a, b) => distanceFromTitle(a) - distanceFromTitle(b));
  const button = candidates[0];
  const text = normalize(button);
  $action
})()
''';
  }

  _FollowState _parseFollowState(Object? result) {
    return switch (_normalizeJavascriptResult(result)) {
      'following' => _FollowState.following,
      'not_following' => _FollowState.notFollowing,
      _ => _FollowState.missing,
    };
  }

  String _normalizeJavascriptResult(Object? result) {
    final value = result?.toString() ?? '';
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      return value.substring(1, value.length - 1);
    }
    return value;
  }
}

enum _FollowState {
  following,
  notFollowing,
  missing,
}
