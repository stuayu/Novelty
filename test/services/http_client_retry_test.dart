import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/services/http_client.dart';

class _StatusSequenceAdapter implements HttpClientAdapter {
  _StatusSequenceAdapter(this._responses);

  final List<ResponseBody> _responses;
  int requestCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final index = requestCount++;
    return _responses[index < _responses.length
        ? index
        : _responses.length - 1];
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('429は指数バックオフ後に上限で打ち切る', () async {
    final delays = <Duration>[];
    final adapter = _StatusSequenceAdapter(<ResponseBody>[
      ResponseBody.fromString('', 429),
      ResponseBody.fromString('', 429),
      ResponseBody.fromString('', 429),
    ]);
    final dio = createNoveltyDio(
      maxRetries: 2,
      retryDelay: (duration) async => delays.add(duration),
    )..httpClientAdapter = adapter;

    await expectLater(
      dio.get<String>('https://example.test/rate-limited'),
      throwsA(
        isA<DioException>().having(
          (error) => error.response?.statusCode,
          'statusCode',
          429,
        ),
      ),
    );

    expect(adapter.requestCount, 3);
    expect(
      delays,
      <Duration>[const Duration(seconds: 1), const Duration(seconds: 2)],
    );
  });

  test('Retry-After秒数を指数バックオフより優先する', () async {
    final delays = <Duration>[];
    final adapter = _StatusSequenceAdapter(<ResponseBody>[
      ResponseBody.fromString(
        '',
        429,
        headers: <String, List<String>>{
          'retry-after': <String>['7'],
        },
      ),
      ResponseBody.fromString('ok', 200),
    ]);
    final dio = createNoveltyDio(
      retryDelay: (duration) async => delays.add(duration),
    )..httpClientAdapter = adapter;

    final response = await dio.get<String>('https://example.test/retry-after');

    expect(response.statusCode, 200);
    expect(adapter.requestCount, 2);
    expect(delays, <Duration>[const Duration(seconds: 7)]);
  });

  test('Retry-AfterのHTTP-dateを現在時刻からの待機時間へ変換する', () async {
    final delays = <Duration>[];
    final adapter = _StatusSequenceAdapter(<ResponseBody>[
      ResponseBody.fromString(
        '',
        503,
        headers: <String, List<String>>{
          'retry-after': <String>['Mon, 24 Aug 2026 00:00:05 GMT'],
        },
      ),
      ResponseBody.fromString('ok', 200),
    ]);
    final dio = createNoveltyDio(
      now: () => DateTime.utc(2026, 8, 24),
      retryDelay: (duration) async => delays.add(duration),
    )..httpClientAdapter = adapter;

    final response = await dio.get<String>('https://example.test/unavailable');

    expect(response.statusCode, 200);
    expect(delays, <Duration>[const Duration(seconds: 5)]);
  });

  test('validateStatusが429を許可しても再試行する', () async {
    final delays = <Duration>[];
    final adapter = _StatusSequenceAdapter(<ResponseBody>[
      ResponseBody.fromString('', 429),
      ResponseBody.fromString('ok', 200),
    ]);
    final dio = createNoveltyDio(
      retryDelay: (duration) async => delays.add(duration),
    )..httpClientAdapter = adapter;

    final response = await dio.get<String>(
      'https://example.test/accepted-rate-limit',
      options: Options(validateStatus: (_) => true),
    );

    expect(response.statusCode, 200);
    expect(adapter.requestCount, 2);
    expect(delays, <Duration>[const Duration(seconds: 1)]);
  });
}
