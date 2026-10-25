import 'package:dio/dio.dart';

/// Dio例外から、クエリや本文を含まない診断項目を作成する。
Map<String, Object?> dioExceptionDiagnosticFields(DioException error) {
  final uri = error.requestOptions.uri;
  return <String, Object?>{
    'errorType': error.runtimeType.toString(),
    'dioType': error.type.name,
    'httpStatusCode': error.response?.statusCode,
    'requestMethod': error.requestOptions.method,
    'requestRoute': '${uri.host}${uri.path}',
  };
}
