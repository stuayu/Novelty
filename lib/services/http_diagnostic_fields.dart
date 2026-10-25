import 'package:dio/dio.dart';

/// サイト固有HTTP例外から、クエリを除いた安全な診断項目を作成する。
Map<String, Object?> httpStatusDiagnosticFields({
  required int statusCode,
  required String method,
  required String url,
}) {
  final uri = Uri.tryParse(url);
  return <String, Object?>{
    'httpStatusCode': statusCode,
    'requestMethod': method,
    if (uri != null && uri.hasAuthority)
      'requestRoute': '${uri.host}${uri.path}',
  };
}

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
