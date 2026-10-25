import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:novelty/services/narou_auth_diagnostics.dart';

/// デバッグビルドのHTTP送受信データをTraceログへ記録する。
class DebugHttpTraceInterceptor extends Interceptor {
  /// 診断ログを指定してインターセプターを作成する。
  DebugHttpTraceInterceptor({required AppDiagnosticsLogger diagnostics})
    : _diagnostics = diagnostics;

  static const _operationIdKey = 'noveltyHttpTraceOperationId';
  static const _startedAtKey = 'noveltyHttpTraceStartedAt';

  final AppDiagnosticsLogger _diagnostics;

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) {
    final operationId =
        options.extra[_operationIdKey] as String? ??
        _diagnostics.createOperationId();
    options.extra[_operationIdKey] = operationId;
    options.extra[_startedAtKey] = DateTime.now()
        .toUtc()
        .millisecondsSinceEpoch;

    _diagnostics.recordTrace(operationId, 'http.request.trace', {
      'method': options.method,
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
    final operationId = _operationId(request);
    _diagnostics.recordTrace(operationId, 'http.response.trace', {
      'method': request.method,
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
    final operationId = _operationId(request);
    _diagnostics.recordTrace(operationId, 'http.error.trace', {
      'method': request.method,
      'requestUrl': request.uri.toString(),
      'requestHeaders': _jsonSafe(request.headers),
      'requestData': _traceData(request.data),
      'responseUrl': response?.realUri.toString(),
      'statusCode': response?.statusCode,
      'responseHeaders': response == null
          ? null
          : _jsonSafe(response.headers.map),
      'responseData': response == null ? null : _traceData(response.data),
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
