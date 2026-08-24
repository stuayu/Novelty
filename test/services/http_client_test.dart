import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/services/http_client.dart';
import 'package:novelty/utils/user_agents.dart';

class _DelayedResponseAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 30));
    throw DioException.receiveTimeout(
      timeout: options.receiveTimeout!,
      requestOptions: options,
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('共通DioはタイムアウトとUser-Agentを設定する', () {
    final dio = createNoveltyDio();

    expect(dio.options.connectTimeout, const Duration(seconds: 15));
    expect(dio.options.receiveTimeout, const Duration(seconds: 30));
    expect(dio.options.sendTimeout, const Duration(seconds: 30));
    // User-Agent は実行環境のプリセットに追随する
    expect(dio.options.headers['User-Agent'], defaultUserAgent);
    expect(dio.options.headers['User-Agent'], startsWith('Mozilla/5.0'));
  });

  test('遅延レスポンスはreceiveTimeoutになる', () async {
    final dio = createNoveltyDio(
      connectTimeout: const Duration(milliseconds: 10),
      receiveTimeout: const Duration(milliseconds: 10),
      sendTimeout: const Duration(milliseconds: 10),
    )..httpClientAdapter = _DelayedResponseAdapter();

    await expectLater(
      dio.get<void>('https://example.test/slow'),
      throwsA(
        isA<DioException>().having(
          (error) => error.type,
          'type',
          DioExceptionType.receiveTimeout,
        ),
      ),
    );
  });
}
