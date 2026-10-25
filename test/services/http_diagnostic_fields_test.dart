import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/services/http_diagnostic_fields.dart';

void main() {
  test('Dio例外の診断項目はURLクエリなどの機密情報を含めない', () {
    final requestOptions = RequestOptions(
      path: 'https://kakuyomu.jp/login?token=private-token',
      method: 'POST',
    );
    final error = DioException(
      requestOptions: requestOptions,
      type: DioExceptionType.badResponse,
      response: Response<dynamic>(
        requestOptions: requestOptions,
        statusCode: 403,
      ),
    );

    final fields = dioExceptionDiagnosticFields(error);

    expect(fields['errorType'], 'DioException');
    expect(fields['dioType'], 'badResponse');
    expect(fields['httpStatusCode'], 403);
    expect(fields['requestMethod'], 'POST');
    expect(fields['requestRoute'], 'kakuyomu.jp/login');
    expect(fields.values.join(' '), isNot(contains('private-token')));
  });
}
