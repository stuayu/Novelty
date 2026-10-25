import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:novelty/services/debug_http_trace_policy.dart';
import 'package:novelty/services/narou_auth_diagnostics.dart';
import 'package:novelty/sites/novel_source.dart';

/// デバッグビルドのHTTP送受信データをTraceログへ記録する。
class DebugHttpTraceInterceptor extends Interceptor {
  /// 診断ログを指定してインターセプターを作成する。
  DebugHttpTraceInterceptor({required AppDiagnosticsLogger diagnostics})
    : _diagnostics = diagnostics;

  static const _operationIdKey = 'noveltyHttpTraceOperationId';
  static const _startedAtKey = 'noveltyHttpTraceStartedAt';
  static const _siteKey = 'noveltyHttpTraceSite';

  final AppDiagnosticsLogger _diagnostics;

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) {
    final source = DebugHttpTracePolicy.sourceForUrl(options.uri.toString());
    if (source == null) {
      handler.next(options);
      return;
    }

    final operationId =
        options.extra[_operationIdKey] as String? ??
        _diagnostics.createOperationId();
    options.extra[_operationIdKey] = operationId;
    options.extra[_siteKey] = source;
    options.extra[_startedAtKey] = DateTime.now()
        .toUtc()
        .millisecondsSinceEpoch;

    _diagnostics.recordTrace(operationId, 'http.request.trace', {
      'method': options.method,
      'site': source.dbId,
      'requestUrl': options.uri.toString(),
      'requestHeaders': _jsonSafe(options.headers),
      'requestData': _traceData(options.data),
      'contentType': options.contentType,
      'responseType': options.responseType.name,
    });
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    final request = response.requestOptions;
    final source = request.extra[_siteKey];
    if (source is! NovelSource ||
        DebugHttpTracePolicy.sourceForUrl(response.realUri.toString()) !=
            source) {
      handler.next(response);
      return;
    }
    final operationId = _operationId(request);
    _diagnostics.recordTrace(operationId, 'http.response.trace', {
      'method': request.method,
      'site': source.dbId,
      'requestUrl': request.uri.toString(),
      'responseUrl': response.realUri.toString(),
      'statusCode': response.statusCode,
      'responseHeaders': _jsonSafe(response.headers.map),
      'responseData': _traceData(response.data),
      'durationMs': _durationMs(request),
    });
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final request = err.requestOptions;
    final response = err.response;
    final source = request.extra[_siteKey];
    if (source is! NovelSource) {
      handler.next(err);
      return;
    }
    final trustedResponse =
        response != null &&
        DebugHttpTracePolicy.sourceForUrl(response.realUri.toString()) ==
            source;
    final operationId = _operationId(request);
    _diagnostics.recordTrace(operationId, 'http.error.trace', {
      'method': request.method,
      'site': source.dbId,
      'requestUrl': request.uri.toString(),
      'requestHeaders': _jsonSafe(request.headers),
      'requestData': _traceData(request.data),
      'responseUrl': trustedResponse ? response.realUri.toString() : null,
      'statusCode': trustedResponse ? response.statusCode : null,
      'responseHeaders': !trustedResponse
          ? null
          : _jsonSafe(response.headers.map),
      'responseData': !trustedResponse ? null : _traceData(response.data),
      'errorType': err.type.name,
      'error': err.toString(),
      'stackTrace': err.stackTrace.toString(),
      'durationMs': _durationMs(request),
    });
    handler.next(err);
  }

  String _operationId(RequestOptions request) {
    final existing = request.extra[_operationIdKey] as String?;
    if (existing != null) return existing;
    final created = _diagnostics.createOperationId();
    request.extra[_operationIdKey] = created;
    return created;
  }

  int? _durationMs(RequestOptions request) {
    final startedAt = request.extra[_startedAtKey] as int?;
    if (startedAt == null) return null;
    return DateTime.now().toUtc().millisecondsSinceEpoch - startedAt;
  }

  Object? _traceData(Object? value) {
    if (value is FormData) {
      return <String, Object?>{
        'fields': <Map<String, String>>[
          for (final field in value.fields)
            <String, String>{'name': field.key, 'value': field.value},
        ],
        'files': <Map<String, Object?>>[
          for (final file in value.files)
            <String, Object?>{
              'name': file.key,
              'filename': file.value.filename,
              'length': file.value.length,
            },
        ],
      };
    }
    if (value is Uint8List) {
      return <String, Object?>{
        'binary': true,
        'byteLength': value.length,
      };
    }
    return _jsonSafe(value);
  }

  Object? _jsonSafe(Object? value) {
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    if (value is DateTime) return value.toIso8601String();
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries)
          entry.key.toString(): _jsonSafe(entry.value),
      };
    }
    if (value is Iterable) return value.map(_jsonSafe).toList();
    return value.toString();
  }
}
