import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/services/debug_webview_http_trace.dart';
import 'package:novelty/services/narou_auth_diagnostics.dart';

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
      site: 'kakuyomu',
      trustedHosts: const <String>['kakuyomu.jp'],
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
      site: 'kakuyomu',
      trustedHosts: const <String>['kakuyomu.jp'],
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
}
