import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:novelty/sites/hameln/hameln_html_fetcher.dart';

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
  final deadline = DateTime.now().add(_webViewTimeout);
  try {
    final loaded = Completer<void>();
    webView = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(url)),
      onLoadStop: (_, _) {
        if (!loaded.isCompleted) loaded.complete();
      },
    );
    await webView.run().timeout(_remaining(deadline));
    await loaded.future.timeout(_remaining(deadline));
    var polls = 0;
    while (true) {
      final controller = webView.webViewController;
      final evaluated = await controller?.evaluateJavascript(
        source: 'document.documentElement.outerHTML',
      );
      final html = evaluated is String ? evaluated : evaluated?.toString();
      polls++;
      if (html != null && html.isNotEmpty && !isHamelnChallengeHtml(html)) {
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
