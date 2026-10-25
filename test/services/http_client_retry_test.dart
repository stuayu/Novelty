import 'dart:async';
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
  for (final statusCode in <int>[429, 503]) {
    test('POSTの$statusCodeは既定のvalidateStatusで再試行しない', () async {
      final delays = <Duration>[];
      final adapter = _StatusSequenceAdapter(<ResponseBody>[
        ResponseBody.fromString('', statusCode),
        ResponseBody.fromString('', statusCode),
      ]);
      final dio = createNoveltyDio(
        maxRetries: 1,
        retryDelay: (duration) async => delays.add(duration),
      )..httpClientAdapter = adapter;

      await expectLater(
        dio.post<String>('https://example.test/post-retry-guard'),
        throwsA(
          isA<DioException>().having(
            (error) => error.response?.statusCode,
            'statusCode',
            statusCode,
          ),
        ),
      );

      expect(adapter.requestCount, 1);
      expect(delays, isEmpty);
    });

    test('POSTの$statusCodeはvalidateStatusが許可しても再試行しない', () async {
      final delays = <Duration>[];
      final adapter = _StatusSequenceAdapter(<ResponseBody>[
        ResponseBody.fromString('', statusCode),
        ResponseBody.fromString('', statusCode),
      ]);
      final dio = createNoveltyDio(
        maxRetries: 1,
        retryDelay: (duration) async => delays.add(duration),
      )..httpClientAdapter = adapter;

      final response = await dio.post<String>(
        'https://example.test/accepted-post-retry-guard',
        options: Options(validateStatus: (_) => true),
      );

      expect(response.statusCode, statusCode);
      expect(adapter.requestCount, 1);
      expect(delays, isEmpty);
    });
  }

  test('429は再試行上限を超えても解除後にGETを再開する', () async {
    final delays = <Duration>[];
    final adapter = _StatusSequenceAdapter(<ResponseBody>[
      ResponseBody.fromString('', 429),
      ResponseBody.fromString('', 429),
      ResponseBody.fromString('', 429),
      ResponseBody.fromString('ok', 200),
    ]);
    final dio = createNoveltyDio(
      maxRetries: 2,
      retryDelay: (duration) async => delays.add(duration),
    )..httpClientAdapter = adapter;

    final response = await dio.get<String>(
      'https://example.test/rate-limited',
    );

    expect(response.data, 'ok');
    expect(adapter.requestCount, 4);
    expect(
      delays,
      <Duration>[
        const Duration(seconds: 1),
        const Duration(seconds: 2),
        const Duration(seconds: 4),
      ],
    );
  });

  test('長いRetry-After待機中でもキャンセルできる', () async {
    final delayStarted = Completer<void>();
    final releaseDelay = Completer<void>();
    final adapter = _StatusSequenceAdapter(<ResponseBody>[
      ResponseBody.fromString(
        '',
        429,
        headers: <String, List<String>>{
          'retry-after': <String>['3600'],
        },
      ),
      ResponseBody.fromString('ok', 200),
    ]);
    final dio = createNoveltyDio(
      retryDelay: (_) {
        if (!delayStarted.isCompleted) delayStarted.complete();
        return releaseDelay.future;
      },
    )..httpClientAdapter = adapter;
    final cancelToken = CancelToken();

    final request = dio.get<String>(
      'https://example.test/cancel-rate-limit',
      cancelToken: cancelToken,
    );
    await delayStarted.future;
    cancelToken.cancel('画面を閉じました');

    await expectLater(
      request,
      throwsA(
        isA<DioException>().having(
          (error) => error.type,
          'type',
          DioExceptionType.cancel,
        ),
      ),
    );
    expect(adapter.requestCount, 1);
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

  test('更新を行うGETは明示的に再試行を禁止できる', () async {
    final adapter = _StatusSequenceAdapter(<ResponseBody>[
      ResponseBody.fromString('', 429),
      ResponseBody.fromString('must not run', 200),
    ]);
    final dio = createNoveltyDio(
      maxRetries: 1,
      retryDelay: (_) async {},
    )..httpClientAdapter = adapter;

    await expectLater(
      dio.get<String>(
        'https://example.test/update',
        options: Options(extra: <String, Object>{'noveltyRetrySafe': false}),
      ),
      throwsA(
        isA<DioException>().having(
          (error) => error.response?.statusCode,
          'statusCode',
          429,
        ),
      ),
    );
    expect(adapter.requestCount, 1);
  });
}
