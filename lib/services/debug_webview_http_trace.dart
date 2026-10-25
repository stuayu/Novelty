import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:novelty/services/debug_http_trace_policy.dart';
import 'package:novelty/services/narou_auth_diagnostics.dart';
import 'package:novelty/sites/novel_source.dart';

/// デバッグビルドのWebView内fetch/XHR通信をTraceログへ記録する。
class DebugWebViewHttpTrace {
  /// 診断ロガーと記録対象サイトを指定する。
  DebugWebViewHttpTrace({
    required AppDiagnosticsLogger diagnostics,
    required this.source,
    String? operationId,
  }) : _diagnostics = diagnostics,
       _operationId = operationId ?? diagnostics.createOperationId();

  /// JavaScriptからTraceデータを受け取るハンドラ名。
  static const String handlerName = 'noveltyHttpTrace';
  static const int _maxBodyCharacters = 512 * 1024;

  final AppDiagnosticsLogger _diagnostics;

  /// Traceログに付けるサイト識別子と公式URL。
  final NovelSource source;
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

  /// WebViewのページ遷移応答から、HTTPメタデータをTraceに記録する。
  NavigationResponseAction recordNavigationResponse(
    NavigationResponse navigationResponse,
  ) {
    final response = navigationResponse.response;
    final url = response?.url?.toString();
    if (_enabled &&
        navigationResponse.isForMainFrame &&
        url != null &&
        _isTrustedUrl(url)) {
      recordJavaScriptEvent(<String, Object?>{
        'phase': 'navigationResponse',
        'url': url,
        'statusCode': response?.statusCode,
        'responseHeaders': response?.headers,
        'mimeType': response?.mimeType,
        'expectedContentLength': response?.expectedContentLength,
        'isForMainFrame': navigationResponse.isForMainFrame,
      });
    }
    return NavigationResponseAction.ALLOW;
  }

  /// 読込完了後の描画済みHTMLをTraceに記録する。
  Future<void> recordRenderedDocument(
    InAppWebViewController controller,
    WebUri? url,
  ) async {
    if (!_enabled || url == null || !_isTrustedUrl(url.toString())) return;

    try {
      final encoded = await controller.evaluateJavascript(
        source:
            'JSON.stringify({title: document.title, '
            'html: document.documentElement?.outerHTML ?? "", '
            'isForMainFrame: window === window.top})',
      );
      final Object? snapshot = switch (encoded) {
        final String value => jsonDecode(value),
        final Map<Object?, Object?> value => value,
        _ => null,
      };
      if (snapshot is! Map<Object?, Object?>) return;
      recordJavaScriptEvent(<String, Object?>{
        'phase': 'document',
        'url': url.toString(),
        'title': snapshot['title'],
        'responseData': snapshot['html'],
        'isForMainFrame': snapshot['isForMainFrame'],
      });
    } on Object {
      // WebViewのページ遷移をログ取得の失敗で止めない。
    }
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
      'navigationResponse' => 'http.webview.navigation.response.trace',
      'document' => 'http.webview.document.trace',
      _ => null,
    };
    if (eventName == null) return;

    _diagnostics.recordTrace(_operationId, eventName, <String, Object?>{
      'site': source.dbId,
      'requestId': fields['requestId'],
      'method': fields['method'],
      'requestUrl': url,
      if (phase == 'request') ...<String, Object?>{
        'requestKind': fields['requestKind'],
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
        'responseUrl': fields['responseUrl'] ?? url,
        'statusCode': fields['statusCode'],
        'statusText': fields['statusText'],
        'responseHeaders': _jsonSafe(fields['responseHeaders']),
        'responseData': _jsonSafe(fields['responseData']),
        'responseDataTruncated': fields['responseDataTruncated'] == true,
        'error': fields['error'],
        'durationMs': fields['durationMs'],
      },
      if (phase == 'navigationResponse') ...<String, Object?>{
        'responseUrl': url,
        'statusCode': fields['statusCode'],
        'responseHeaders': _jsonSafe(fields['responseHeaders']),
        'mimeType': fields['mimeType'],
        'expectedContentLength': fields['expectedContentLength'],
        'isForMainFrame': fields['isForMainFrame'] == true,
        'responseBodyAvailable': false,
      },
      if (phase == 'document') ...<String, Object?>{
        'title': fields['title'],
        'responseData': _capText(fields['responseData']).value,
        'responseDataTruncated': _capText(fields['responseData']).truncated,
        'isForMainFrame': fields['isForMainFrame'] == true,
      },
    });
  }

  bool _isTrustedUrl(String rawUrl) {
    return DebugHttpTracePolicy.isTrustedUrl(rawUrl, source);
  }

  _CappedTraceValue _capText(Object? value) {
    if (value is! String || value.length <= _maxBodyCharacters) {
      return _CappedTraceValue(value: value, truncated: false);
    }
    return _CappedTraceValue(
      value: value.substring(0, _maxBodyCharacters),
      truncated: true,
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
    final hosts = jsonEncode(DebugHttpTracePolicy.hostsFor(source).toList());
    return '''
(() => {
  if (window.__noveltyHttpTraceInstalled) return;
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
  const captureFormSubmission = () => {
    document.addEventListener('submit', (event) => {
      const form = event.target;
      if (!(form instanceof HTMLFormElement)) return;
      const method = String(form.method || 'GET').toUpperCase();
      const action = new URL(form.action || window.location.href, window.location.href);
      if (!isTrusted(action.href)) return;
      const entries = Array.from(new FormData(form).entries()).map(([name, value]) =>
        [name, typeof value === 'string' ? value : {
          filename: value.name, type: value.type, size: value.size
        }]);
      if (method === 'GET') {
        entries.forEach(([name, value]) => {
          if (typeof value === 'string') action.searchParams.append(name, value);
        });
      }
      const requestData = capBody(entries);
      emit({phase: 'request', requestId: 'form-' + (++requestSequence),
        requestKind: 'html-form', method, url: action.href,
        requestHeaders: {}, requestData: requestData.value,
        requestDataTruncated: requestData.truncated});
    }, true);
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
  const bodyToTraceValue = (body) => {
    try {
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
  const bodyToValue = async (body, request) => {
    try {
      if (body == null && request instanceof Request && request.method !== 'GET' && request.method !== 'HEAD') {
        body = await request.clone().text();
      }
      return bodyToTraceValue(body);
    } catch (_) {
      return '[unavailable]';
    }
  };
  const capBody = (value) => {
    const serialized = typeof value === 'string' ? value : JSON.stringify(value);
    if (serialized == null || serialized.length <= maxBodyCharacters) {
      return {value, truncated: false};
    }
    return {value: serialized.slice(0, maxBodyCharacters), truncated: true};
  };
  const installXhrTrace = () => {
    const OriginalXhr = window.XMLHttpRequest;
    if (typeof OriginalXhr !== 'function') return;
    const requestState = new WeakMap();
    const originalOpen = OriginalXhr.prototype.open;
    OriginalXhr.prototype.open = function(requestMethod, requestUrl) {
      requestState.set(this, {
        method: String(requestMethod || 'GET').toUpperCase(),
        url: new URL(String(requestUrl), window.location.href).href,
        requestHeaders: {},
      });
      return originalOpen.apply(this, arguments);
    };
    const originalSetRequestHeader = OriginalXhr.prototype.setRequestHeader;
    OriginalXhr.prototype.setRequestHeader = function(name, value) {
      const state = requestState.get(this);
      if (state) state.requestHeaders[String(name)] = String(value);
      return originalSetRequestHeader.apply(this, arguments);
    };
    const originalSend = OriginalXhr.prototype.send;
    OriginalXhr.prototype.send = function(body) {
      const state = requestState.get(this);
      if (!state || !isTrusted(state.url)) {
        return originalSend.apply(this, arguments);
      }
      const {method, url, requestHeaders} = state;
      const requestId = 'xhr-' + (++requestSequence);
      const startedAt = Date.now();
      const requestData = capBody(bodyToTraceValue(body));
      emit({phase: 'request', requestId, method, url,
        requestHeaders: {...requestHeaders}, requestData: requestData.value,
        requestDataTruncated: requestData.truncated});
      this.addEventListener('loadend', () => {
        let responseData = null;
        try {
          if (this.responseType === '' || this.responseType === 'text') {
            responseData = this.responseText;
          } else if (this.responseType === 'json') {
            responseData = JSON.stringify(this.response);
          } else if (this.responseType === 'document' && this.responseXML) {
            responseData = this.responseXML.documentElement.outerHTML;
          } else {
            responseData = {binary: true, responseType: this.responseType};
          }
        } catch (_) {
          responseData = '[unavailable]';
        }
        const responseBody = capBody(responseData);
        const responseHeaders = {};
        try {
          this.getAllResponseHeaders().trim().split(/\\r?\\n/).forEach((line) => {
            const separator = line.indexOf(':');
            if (separator > 0) responseHeaders[line.slice(0, separator).trim()] = line.slice(separator + 1).trim();
          });
        } catch (_) {}
        const responseEvent = {requestId, method, url, responseUrl: this.responseURL || url,
          statusCode: this.status, statusText: this.statusText, responseHeaders,
          responseData: responseBody.value, responseDataTruncated: responseBody.truncated,
          durationMs: Date.now() - startedAt};
        if (this.status === 0) {
          emit({phase: 'error', ...responseEvent, error: this.statusText || 'network-error'});
        } else {
          emit({phase: 'response', ...responseEvent});
        }
      }, {once: true});
      try {
        return originalSend.apply(this, arguments);
      } catch (error) {
        emit({phase: 'error', requestId, method, url, error: String(error),
          durationMs: Date.now() - startedAt});
        throw error;
      }
    };
  };
  const install = () => {
    if (window.__noveltyHttpTraceInstalled) return;
    window.__noveltyHttpTraceInstalled = true;
    installXhrTrace();
    captureFormSubmission();
    if (typeof window.fetch !== 'function') return;
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
        void requestTrace.then(() => emit({phase: 'error', requestId, method,
          url: requestUrl, error: String(error),
          durationMs: Date.now() - startedAt}));
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

class _CappedTraceValue {
  const _CappedTraceValue({required this.value, required this.truncated});

  final Object? value;
  final bool truncated;
}
