import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:novelty/services/debug_webview_http_trace.dart';
import 'package:novelty/services/narou_auth_diagnostics.dart';
import 'package:novelty/sites/hameln/hameln_html_fetcher.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:novelty/utils/hameln_uri.dart';

const _hamelnBaseUrl = 'https://syosetu.org/';
const _pollInterval = Duration(milliseconds: 250);
const _webViewTimeout = Duration(seconds: 30);

Future<void> _lastWebViewOperation = Future<void>.value();

/// Headless WebViewでハーメルンのHTMLを取得する。
HamelnHtmlFetcher get defaultHamelnHtmlFetcher => fetchHamelnHtmlWithWebView;

/// Headless WebViewが保存したCookieをDioのCookieヘッダーへ変換する。
HamelnCookieHeaderFetcher get defaultHamelnCookieHeaderFetcher =>
    readHamelnCookieHeader;

/// Cloudflareのチャレンジ解決後のHTMLを取得する。
Future<String> fetchHamelnHtmlWithWebView(String url) {
  final operation = _lastWebViewOperation.then((_) => _fetch(url));
  // 後続処理は前処理の失敗で停止させない。個別の失敗は呼び出し元へ返す。
  _lastWebViewOperation = operation.then<void>(
    (_) {},
    onError: (_, _) {},
  );
  return operation;
}

Future<String> _fetch(String url) async {
  HeadlessInAppWebView? webView;
  final webViewTrace = DebugWebViewHttpTrace(
    diagnostics: appDiagnosticsLogger,
    source: NovelSource.hameln,
  );
  final deadline = DateTime.now().add(_webViewTimeout);
  try {
    final loaded = Completer<void>();
    var blockedNavigation = false;
    webView = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(url)),
      initialSettings: InAppWebViewSettings(
        useShouldOverrideUrlLoading: true,
        useOnNavigationResponse: true,
      ),
      initialUserScripts: webViewTrace.initialUserScripts,
      onWebViewCreated: webViewTrace.registerHandler,
      onNavigationResponse: (_, response) async =>
          webViewTrace.recordNavigationResponse(response),
      shouldOverrideUrlLoading: (_, action) async {
        final uri = action.request.url?.uriValue;
        final allowed = action.isForMainFrame
            ? isAllowedHamelnNavigationUri(uri)
            : isAllowedHamelnSubframeNavigationUri(uri);
        if (!allowed && action.isForMainFrame) blockedNavigation = true;
        return allowed
            ? NavigationActionPolicy.ALLOW
            : NavigationActionPolicy.CANCEL;
      },
      onLoadStop: (controller, url) async {
        await webViewTrace.recordRenderedDocument(controller, url);
        if (!loaded.isCompleted) loaded.complete();
      },
    );
    await webView.run().timeout(_remaining(deadline));
    await loaded.future.timeout(_remaining(deadline));
    final finalUrl = await webView.webViewController?.getUrl();
    if (blockedNavigation ||
        !isAllowedHamelnNavigationUri(finalUrl?.uriValue)) {
      throw StateError('WebViewが許可されていない転送先へ移動しました: $url');
    }
    var polls = 0;
    while (true) {
      if (blockedNavigation) {
        throw StateError('WebViewが許可されていない転送先へ移動しました: $url');
      }
      final controller = webView.webViewController;
      final evaluated = await controller?.evaluateJavascript(
        source: 'document.documentElement.outerHTML',
      );
      final html = evaluated is String ? evaluated : evaluated?.toString();
      polls++;
      if (html != null && html.isNotEmpty && !isHamelnChallengeHtml(html)) {
        if (controller != null) {
          await webViewTrace.recordRenderedDocument(controller, finalUrl);
        }
        debugPrint('[HamelnWebView] $url を取得 (${html.length}文字, $polls回目)');
        return html;
      }
      if (DateTime.now().isAfter(deadline)) {
        debugPrint(
          '[HamelnWebView] $url がチャレンジのまま時間切れ '
          '($polls回試行, 最終HTML=${html?.length ?? 0}文字)',
        );
        throw TimeoutException('ハーメルンCloudflareチャレンジが解決しません');
      }
      await Future<void>.delayed(_pollInterval);
    }
  } finally {
    await webView?.dispose();
  }
}

Duration _remaining(DateTime deadline) {
  final remaining = deadline.difference(DateTime.now());
  return remaining.isNegative ? Duration.zero : remaining;
}

/// WebViewのCookieManagerからハーメルンCookieを読み込む。
Future<String?> readHamelnCookieHeader(String url) async {
  final cookies = await CookieManager.instance().getCookies(
    url: WebUri(_hamelnBaseUrl),
  );
  if (cookies.isEmpty) return null;
  return cookies.map((cookie) => '${cookie.name}=${cookie.value}').join('; ');
}
