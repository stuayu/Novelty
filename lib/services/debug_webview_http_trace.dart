import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:novelty/services/narou_auth_diagnostics.dart';

/// デバッグビルドのWebView内fetch通信をTraceログへ記録する。
class DebugWebViewHttpTrace {
  /// 診断ロガーと記録対象サイトを指定する。
  DebugWebViewHttpTrace({
    required AppDiagnosticsLogger diagnostics,
    required this.site,
    required Iterable<String> trustedHosts,
    String? operationId,
  }) : _diagnostics = diagnostics,
       _trustedHosts = trustedHosts.map((host) => host.toLowerCase()).toSet(),
       _operationId = operationId ?? diagnostics.createOperationId();

  /// JavaScriptからTraceデータを受け取るハンドラ名。
  static const String handlerName = 'noveltyHttpTrace';
  static const int _maxBodyCharacters = 512 * 1024;

  final AppDiagnosticsLogger _diagnostics;

  /// Traceログに付けるサイト識別子。
  final String site;
  final Set<String> _trustedHosts;
  final String _operationId;

  /// 診断ログの初期化設定。
  UnmodifiableListView<UserScript> get initialUserScripts {
    if (!_enabled) return UnmodifiableListView<UserScript>(const []);
    return UnmodifiableListView<UserScript>(<UserScript>[
      UserScript(
        source: _fetchTraceScript,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        forMainFrameOnly: false,
      ),
    ]);
  }

  bool get _enabled => kDebugMode && _diagnostics.captureSensitiveTrace;

  /// WebViewからの通信Traceを受け取るJavaScriptハンドラを登録する。
  void registerHandler(InAppWebViewController controller) {
    if (!_enabled) return;
    controller.addJavaScriptHandler(
      handlerName: handlerName,
      callback: (arguments) {
        if (arguments.isNotEmpty) recordJavaScriptEvent(arguments.first);
        return null;
      },
    );
  }

  /// WebView内の通信イベントを検証し、Traceログへ記録する。
  void recordJavaScriptEvent(Object? event) {
    if (!_enabled || event is! Map) return;
    final fields = <String, Object?>{
      for (final entry in event.entries) entry.key.toString(): entry.value,
    };
    final url = fields['url']?.toString();
    if (url == null || !_isTrustedUrl(url)) return;

    final phase = fields['phase'];
    final eventName = switch (phase) {
      'request' => 'http.webview.request.trace',
      'response' => 'http.webview.response.trace',
      'error' => 'http.webview.error.trace',
      _ => null,
    };
    if (eventName == null) return;

    _diagnostics.recordTrace(_operationId, eventName, <String, Object?>{
      'site': site,
      'requestId': fields['requestId'],
      'method': fields['method'],
      'requestUrl': url,
      if (phase == 'request') ...<String, Object?>{
        'requestHeaders': _jsonSafe(fields['requestHeaders']),
        'requestData': _jsonSafe(fields['requestData']),
        'requestDataTruncated': fields['requestDataTruncated'] == true,
      },
      if (phase == 'response') ...<String, Object?>{
        'responseUrl': fields['responseUrl'] ?? url,
        'statusCode': fields['statusCode'],
        'statusText': fields['statusText'],
        'responseHeaders': _jsonSafe(fields['responseHeaders']),
        'responseData': _jsonSafe(fields['responseData']),
        'responseDataTruncated': fields['responseDataTruncated'] == true,
        'durationMs': fields['durationMs'],
      },
      if (phase == 'error') ...<String, Object?>{
        'error': fields['error'],
        'durationMs': fields['durationMs'],
      },
    });
  }

  bool _isTrustedUrl(String rawUrl) {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || !uri.hasAuthority || uri.scheme != 'https') return false;
    final host = uri.host.toLowerCase();
    return _trustedHosts.any(
      (trustedHost) => host == trustedHost || host.endsWith('.$trustedHost'),
    );
  }

  Object? _jsonSafe(Object? value) {
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries)
          entry.key.toString(): _jsonSafe(entry.value),
      };
    }
    if (value is Iterable) return value.map(_jsonSafe).toList();
    return value.toString();
  }

  String get _fetchTraceScript {
    final hosts = jsonEncode(_trustedHosts.toList());
    return '''
(() => {
  if (window.__noveltyFetchTraceInstalled) return;
  const trustedHosts = $hosts;
  const maxBodyCharacters = $_maxBodyCharacters;
  let requestSequence = 0;
  const isTrusted = (rawUrl) => {
    try {
      const url = new URL(rawUrl, window.location.href);
      return url.protocol === 'https:' && trustedHosts.some((host) =>
        url.hostname === host || url.hostname.endsWith('.' + host));
    } catch (_) {
      return false;
    }
  };
  const emit = (event) => {
    try {
      const bridge = window.flutter_inappwebview;
      if (bridge && typeof bridge.callHandler === 'function') {
        const pending = bridge.callHandler('$handlerName', event);
        if (pending && typeof pending.catch === 'function') pending.catch(() => {});
      }
    } catch (_) {}
  };
  const headersToObject = (headers) => {
    try {
      const result = {};
      new Headers(headers || {}).forEach((value, key) => { result[key] = value; });
      return result;
    } catch (_) {
      return {};
    }
  };
  const bodyToValue = async (body, request) => {
    try {
      if (body == null && request instanceof Request && request.method !== 'GET' && request.method !== 'HEAD') {
        body = await request.clone().text();
      }
      if (body == null || typeof body === 'string') return body;
      if (body instanceof URLSearchParams) return body.toString();
      if (body instanceof FormData) {
        return Array.from(body.entries()).map(([name, value]) => [name,
          typeof value === 'string' ? value : {filename: value.name, type: value.type, size: value.size}]);
      }
      if (body instanceof Blob) return {binary: true, byteLength: body.size, contentType: body.type};
      if (body instanceof ArrayBuffer) return {binary: true, byteLength: body.byteLength};
      return String(body);
    } catch (_) {
      return '[unavailable]';
    }
  };
  const capBody = (value) => {
    if (typeof value !== 'string' || value.length <= maxBodyCharacters) {
      return {value, truncated: false};
    }
    return {value: value.slice(0, maxBodyCharacters), truncated: true};
  };
  const install = () => {
    if (window.__noveltyFetchTraceInstalled || typeof window.fetch !== 'function') return;
    window.__noveltyFetchTraceInstalled = true;
    const originalFetch = window.fetch;
    window.fetch = async function(input, init) {
      const request = input instanceof Request ? input : null;
      const url = request ? request.url : String(input);
      if (!isTrusted(url)) return originalFetch.apply(this, arguments);
      const method = String((init && init.method) || (request && request.method) || 'GET').toUpperCase();
      const requestId = 'fetch-' + (++requestSequence);
      const startedAt = Date.now();
      const requestUrl = new URL(url, window.location.href).href;
      const requestHeaders = headersToObject((init && init.headers) || (request && request.headers));
      const requestTrace = bodyToValue(init && init.body, request).then((data) => {
        const requestData = capBody(data);
        emit({phase: 'request', requestId, method, url: requestUrl,
          requestHeaders, requestData: requestData.value,
          requestDataTruncated: requestData.truncated});
      });
      try {
        const response = await originalFetch.apply(this, arguments);
        void requestTrace.then(async () => {
          try {
            const responseHeaders = headersToObject(response.headers);
            const contentType = response.headers.get('content-type') || '';
            let responseData = null;
            let responseDataTruncated = false;
            if (response.type !== 'opaque' && /^(text\\/|application\\/(json|[^;]+\\+json|xml|javascript|x-www-form-urlencoded))/i.test(contentType)) {
              const body = capBody(await response.clone().text());
              responseData = body.value;
              responseDataTruncated = body.truncated;
            } else if (response.type !== 'opaque') {
              responseData = {binary: true, contentLength: response.headers.get('content-length')};
            }
            emit({phase: 'response', requestId, method, url: requestUrl,
              responseUrl: response.url, statusCode: response.status, statusText: response.statusText,
              responseHeaders, responseData, responseDataTruncated, durationMs: Date.now() - startedAt});
          } catch (error) {
            emit({phase: 'error', requestId, method, url: requestUrl,
              error: 'response-trace-failed: ' + String(error), durationMs: Date.now() - startedAt});
          }
        });
        return response;
      } catch (error) {
        void requestTrace.then(() => emit({phase: 'error', requestId, method, url: requestUrl,
          error: String(error), durationMs: Date.now() - startedAt}));
        throw error;
      }
    };
  };
  if (window.flutter_inappwebview && typeof window.flutter_inappwebview.callHandler === 'function') {
    install();
  } else {
    window.addEventListener('flutterInAppWebViewPlatformReady', install, {once: true});
  }
})();
''';
  }
}
