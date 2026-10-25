import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/services/debug_webview_http_trace.dart';
import 'package:novelty/services/narou_auth_diagnostics.dart';
import 'package:novelty/sites/novel_source.dart';

void main() {
  test('WebViewのfetch送受信内容とHTTPステータスをTraceへ記録する', () async {
    final directory = await Directory.systemTemp.createTemp(
      'novelty-debug-webview-trace-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final diagnostics = AppDiagnosticsLogger(
      enabled: true,
      directoryResolver: () async => directory,
      consoleSink: (_) {},
    );
    final trace = DebugWebViewHttpTrace(
      diagnostics: diagnostics,
      source: NovelSource.kakuyomu,
    );

    final recordEvent = trace.recordJavaScriptEvent;
    recordEvent(<String, Object?>{
      'phase': 'request',
      'requestId': 'request-1',
      'method': 'POST',
      'url': 'https://kakuyomu.jp/api/v2/auth/login',
      'requestHeaders': <String, String>{'Content-Type': 'application/json'},
      'requestData': '{"email":"user@example.test","password":"secret"}',
    });
    recordEvent(<String, Object?>{
      'phase': 'response',
      'requestId': 'request-1',
      'method': 'POST',
      'url': 'https://kakuyomu.jp/api/v2/auth/login',
      'statusCode': 200,
      'responseHeaders': <String, String>{'content-type': 'application/json'},
      'responseData': '{"redirectLocation":"/"}',
      'durationMs': 42,
    });
    await diagnostics.flush();

    final tracePath = await diagnostics.traceLogFilePath();
    final entries = File(tracePath!)
        .readAsLinesSync()
        .map((line) => jsonDecode(line) as Map<String, dynamic>)
        .toList();
    final request = entries.singleWhere(
      (entry) => entry['event'] == 'http.webview.request.trace',
    );
    final response = entries.singleWhere(
      (entry) => entry['event'] == 'http.webview.response.trace',
    );

    expect(request['requestData'], contains('secret'));
    expect(request['site'], 'kakuyomu');
    expect(response['statusCode'], 200);
    expect(response['responseData'], '{"redirectLocation":"/"}');
    expect(response['durationMs'], 42);
  });

  test('許可したサイト以外のWebView通信はTraceに出さない', () async {
    final directory = await Directory.systemTemp.createTemp(
      'novelty-debug-webview-filter-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final diagnostics = AppDiagnosticsLogger(
      enabled: true,
      directoryResolver: () async => directory,
      consoleSink: (_) {},
    );
    final trace = DebugWebViewHttpTrace(
      diagnostics: diagnostics,
      source: NovelSource.kakuyomu,
    );

    final recordEvent = trace.recordJavaScriptEvent;
    recordEvent(<String, Object?>{
      'phase': 'request',
      'requestId': 'request-1',
      'method': 'POST',
      'url': 'https://third-party.example/collect',
      'requestData': 'private-payload',
    });
    await diagnostics.flush();

    final tracePath = await diagnostics.traceLogFilePath();
    expect(File(tracePath!).existsSync(), isFalse);
  });

  test('WebView通信エラーTraceに要求とHTTP応答の情報を記録する', () async {
    final directory = await Directory.systemTemp.createTemp(
      'novelty-debug-webview-error-trace-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final diagnostics = AppDiagnosticsLogger(
      enabled: true,
      directoryResolver: () async => directory,
      consoleSink: (_) {},
    );
    final recordEvent = DebugWebViewHttpTrace(
      diagnostics: diagnostics,
      source: NovelSource.kakuyomu,
    ).recordJavaScriptEvent;
    recordEvent(<String, Object?>{
      'phase': 'request',
      'requestId': 'xhr-1',
      'method': 'POST',
      'url': 'https://kakuyomu.jp/api/v2/account',
      'requestHeaders': <String, String>{'content-type': 'application/json'},
      'requestData': '{"operationName":"UpdateAccount"}',
    });
    recordEvent(<String, Object?>{
      'phase': 'error',
      'requestId': 'xhr-1',
      'method': 'POST',
      'url': 'https://kakuyomu.jp/api/v2/account',
      'statusCode': 503,
      'statusText': 'Service Unavailable',
      'responseHeaders': <String, String>{'retry-after': '5'},
      'responseData': '{"error":"temporarily unavailable"}',
      'durationMs': 51,
      'error': 'network-error',
    });
    await diagnostics.flush();

    final tracePath = await diagnostics.traceLogFilePath();
    final entries = File(tracePath!)
        .readAsLinesSync()
        .map((line) => jsonDecode(line) as Map<String, dynamic>)
        .toList();
    final request = entries.singleWhere(
      (entry) => entry['event'] == 'http.webview.request.trace',
    );
    final error = entries.singleWhere(
      (entry) => entry['event'] == 'http.webview.error.trace',
    );
    expect(request['requestId'], error['requestId']);
    expect(request['requestData'], '{"operationName":"UpdateAccount"}');
    expect(error['statusCode'], 503);
    expect(error['statusText'], 'Service Unavailable');
    expect(error['responseHeaders'], <String, String>{'retry-after': '5'});
    expect(error['responseData'], '{"error":"temporarily unavailable"}');
    expect(error.containsKey('requestData'), isFalse);
  });

  test('WebViewページ遷移TraceにHTTPステータスと応答ヘッダーを記録する', () async {
    final directory = await Directory.systemTemp.createTemp(
      'novelty-debug-webview-navigation-trace-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final diagnostics = AppDiagnosticsLogger(
      enabled: true,
      directoryResolver: () async => directory,
      consoleSink: (_) {},
    );
    final recordEvent = DebugWebViewHttpTrace(
      diagnostics: diagnostics,
      source: NovelSource.kakuyomu,
    ).recordJavaScriptEvent;
    recordEvent(<String, Object?>{
      'phase': 'navigationResponse',
      'url': 'https://kakuyomu.jp/auth/login',
      'statusCode': 403,
      'responseHeaders': <String, String>{'content-type': 'text/html'},
      'mimeType': 'text/html',
      'expectedContentLength': 80,
      'isForMainFrame': true,
    });
    await diagnostics.flush();

    final tracePath = await diagnostics.traceLogFilePath();
    final entry = File(tracePath!)
        .readAsLinesSync()
        .map((line) => jsonDecode(line) as Map<String, dynamic>)
        .single;
    expect(entry['event'], 'http.webview.navigation.response.trace');
    expect(entry['statusCode'], 403);
    expect(entry['responseHeaders'], <String, String>{
      'content-type': 'text/html',
    });
    expect(entry['mimeType'], 'text/html');
    expect(entry['isForMainFrame'], isTrue);
  });

  test('WebView Traceは標準フォームとネイティブXHRの通信計測を注入する', () {
    final diagnostics = AppDiagnosticsLogger(
      enabled: true,
      consoleSink: (_) {},
    );
    final trace = DebugWebViewHttpTrace(
      diagnostics: diagnostics,
      source: NovelSource.kakuyomu,
    );

    final source = trace.initialUserScripts.single.source;
    expect(source, contains("addEventListener('submit'"));
    expect(source, contains('const requestState = new WeakMap()'));
    expect(source, contains('OriginalXhr.prototype.open = function'));
    expect(source, isNot(contains('window.XMLHttpRequest = TracedXhr')));
  });

  test('ページ遷移後のDOMスナップショットを別Traceイベントに記録する', () async {
    final directory = await Directory.systemTemp.createTemp(
      'novelty-debug-webview-document-trace-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final diagnostics = AppDiagnosticsLogger(
      enabled: true,
      directoryResolver: () async => directory,
      consoleSink: (_) {},
    );
    final recordEvent = DebugWebViewHttpTrace(
      diagnostics: diagnostics,
      source: NovelSource.kakuyomu,
    ).recordJavaScriptEvent;
    recordEvent(<String, Object?>{
      'phase': 'document',
      'url': 'https://kakuyomu.jp/auth/login',
      'title': 'Login',
      'responseData': '<html><body>Login failed</body></html>',
      'isForMainFrame': true,
    });
    await diagnostics.flush();

    final tracePath = await diagnostics.traceLogFilePath();
    final entry = File(tracePath!)
        .readAsLinesSync()
        .map((line) => jsonDecode(line) as Map<String, dynamic>)
        .single;
    expect(entry['event'], 'http.webview.document.trace');
    expect(entry['title'], 'Login');
    expect(entry['responseData'], '<html><body>Login failed</body></html>');
    expect(entry['isForMainFrame'], isTrue);
  });
}
