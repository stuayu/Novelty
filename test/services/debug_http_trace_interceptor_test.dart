import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/services/http_client.dart';
import 'package:novelty/services/narou_auth_diagnostics.dart';

class _ResponseAdapter implements HttpClientAdapter {
  _ResponseAdapter({required this.statusCode, required this.body});

  final int statusCode;
  final String body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: ['text/plain; charset=utf-8'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('HTTP Traceにリクエスト本文・Cookie・応答本文・ステータスを記録する', () async {
    final directory = await Directory.systemTemp.createTemp(
      'novelty-debug-http-trace-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final consoleLines = <String>[];
    final diagnostics = AppDiagnosticsLogger(
      enabled: true,
      directoryResolver: () async => directory,
      consoleSink: consoleLines.add,
    );
    final dio = createNoveltyDio(diagnostics: diagnostics, maxRetries: 0)
      ..httpClientAdapter = _ResponseAdapter(
        statusCode: 200,
        body: 'response-payload',
      );
    addTearDown(dio.close);

    await dio.post<String>(
      'https://kakuyomu.jp/login',
      data: <String, String>{'password': 'request-payload'},
      options: Options(
        responseType: ResponseType.plain,
        headers: <String, Object>{'Cookie': 'session=cookie-payload'},
      ),
    );
    await diagnostics.flush();

    final tracePath = await diagnostics.traceLogFilePath();
    final traceLog = await File(tracePath!).readAsString();
    final entries = traceLog
        .split('\n')
        .where((line) => line.isNotEmpty)
        .map((line) => jsonDecode(line) as Map<String, dynamic>)
        .toList();
    final request = entries.singleWhere(
      (entry) => entry['event'] == 'http.request.trace',
    );
    final response = entries.singleWhere(
      (entry) => entry['event'] == 'http.response.trace',
    );
    final requestHeaders = request['requestHeaders'] as Map<String, dynamic>;
    final requestData = request['requestData'] as Map<String, dynamic>;

    expect(request['requestUrl'], 'https://kakuyomu.jp/login');
    expect(request['site'], 'kakuyomu');
    expect(requestHeaders['Cookie'], 'session=cookie-payload');
    expect(requestData['password'], 'request-payload');
    expect(response['statusCode'], 200);
    expect(response['responseData'], 'response-payload');
    expect(consoleLines, hasLength(2));
  });

  test('HTTPエラーTraceに応答ステータスと本文を記録する', () async {
    final directory = await Directory.systemTemp.createTemp(
      'novelty-debug-http-error-trace-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final diagnostics = AppDiagnosticsLogger(
      enabled: true,
      directoryResolver: () async => directory,
      consoleSink: (_) {},
    );
    final dio = createNoveltyDio(diagnostics: diagnostics, maxRetries: 0)
      ..httpClientAdapter = _ResponseAdapter(
        statusCode: 403,
        body: 'forbidden-response',
      );
    addTearDown(dio.close);

    await expectLater(
      dio.get<String>(
        'https://syosetu.com/library',
        options: Options(responseType: ResponseType.plain),
      ),
      throwsA(isA<DioException>()),
    );
    await diagnostics.flush();

    final tracePath = await diagnostics.traceLogFilePath();
    final traceLog = await File(tracePath!).readAsString();
    final entry = traceLog
        .split('\n')
        .where((line) => line.isNotEmpty)
        .map((line) => jsonDecode(line) as Map<String, dynamic>)
        .singleWhere((entry) => entry['event'] == 'http.error.trace');

    expect(entry['event'], 'http.error.trace');
    expect(entry['statusCode'], 403);
    expect(entry['responseData'], 'forbidden-response');
  });

  test('HTTP Traceの大きな本文は上限で切り詰めて記録する', () async {
    final directory = await Directory.systemTemp.createTemp(
      'novelty-debug-http-trace-cap-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final diagnostics = AppDiagnosticsLogger(
      enabled: true,
      directoryResolver: () async => directory,
      consoleSink: (_) {},
    );
    final body = 'x' * (512 * 1024 + 10);
    final dio = createNoveltyDio(diagnostics: diagnostics, maxRetries: 0)
      ..httpClientAdapter = _ResponseAdapter(statusCode: 200, body: body);
    addTearDown(dio.close);

    await dio.post<String>(
      'https://kakuyomu.jp/login',
      data: body,
      options: Options(responseType: ResponseType.plain),
    );
    await diagnostics.flush();

    final tracePath = await diagnostics.traceLogFilePath();
    final entries = (await File(tracePath!).readAsLines())
        .map((line) => jsonDecode(line) as Map<String, dynamic>)
        .toList();
    final request = entries.singleWhere(
      (entry) => entry['event'] == 'http.request.trace',
    );
    final response = entries.singleWhere(
      (entry) => entry['event'] == 'http.response.trace',
    );

    expect((request['requestData'] as String).length, 512 * 1024);
    expect(request['requestDataTruncated'], isTrue);
    expect((response['responseData'] as String).length, 512 * 1024);
    expect(response['responseDataTruncated'], isTrue);
  });

  test('Noveltyの対象サイト以外のHTTP Traceは出力しない', () async {
    final directory = await Directory.systemTemp.createTemp(
      'novelty-debug-http-external-trace-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final diagnostics = AppDiagnosticsLogger(
      enabled: true,
      directoryResolver: () async => directory,
      consoleSink: (_) {},
    );
    final dio = createNoveltyDio(diagnostics: diagnostics, maxRetries: 0)
      ..httpClientAdapter = _ResponseAdapter(statusCode: 200, body: 'ok');
    addTearDown(dio.close);

    await dio.get<String>(
      'https://external.example.test/private',
      options: Options(responseType: ResponseType.plain),
    );
    await diagnostics.flush();

    final tracePath = await diagnostics.traceLogFilePath();
    expect(File(tracePath!).existsSync(), isFalse);
  });
}
