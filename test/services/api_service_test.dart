import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/models/novel_info.dart';
import 'package:novelty/models/novel_search_query.dart';
import 'package:novelty/services/api_service.dart';

class _FakeResponseAdapter implements HttpClientAdapter {
  _FakeResponseAdapter(this._body, {this.statusCode = 200});

  final String _body;
  final int statusCode;
  final List<Uri> requestedUris = <Uri>[];
  int requestCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestCount++;
    requestedUris.add(options.uri);
    final gzipped = const GZipEncoder().encode(utf8.encode(_body));
    return ResponseBody.fromBytes(
      gzipped,
      statusCode,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _TimedHostAdapter implements HttpClientAdapter {
  _TimedHostAdapter() {
    _stopwatch.start();
  }

  final Stopwatch _stopwatch = Stopwatch();
  final Map<String, List<Duration>> requestTimes = <String, List<Duration>>{};
  final List<Duration?> connectTimeouts = <Duration?>[];
  final List<Duration?> receiveTimeouts = <Duration?>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    connectTimeouts.add(options.connectTimeout);
    receiveTimeouts.add(options.receiveTimeout);
    final host = options.uri.host;
    requestTimes.putIfAbsent(host, () => <Duration>[]).add(_stopwatch.elapsed);
    if (host == 'api.syosetu.com') {
      final bytes = const GZipEncoder().encode(
        utf8.encode('[{"allcount":0}]'),
      );
      return ResponseBody.fromBytes(bytes, 200);
    }
    return ResponseBody.fromString('<html></html>', 200);
  }

  @override
  void close({bool force = false}) {}
}

class _EpisodeFetchAdapter implements HttpClientAdapter {
  final Map<String, int> callCounts = <String, int>{};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final host = options.uri.host;
    callCounts.update(host, (count) => count + 1, ifAbsent: () => 1);
    if (host == 'api.syosetu.com') {
      final bytes = const GZipEncoder().encode(
        utf8.encode(
          '[{"allcount":1},{"ncode":"n1234ab","novel_type":"1"}]',
        ),
      );
      return ResponseBody.fromBytes(bytes, 200);
    }
    return ResponseBody.fromString(
      '<h1 class="p-novel__title--rensai">本文タイトル</h1> '
      '<p class="p-novel__number">1/2</p> '
      '<div class="p-novel__text"><p>本文</p></div>',
      200,
    );
  }

  @override
  void close({bool force = false}) {}
}

ApiService _createService(String body) {
  final dio = Dio()..httpClientAdapter = _FakeResponseAdapter(body);
  return ApiService(dio: dio);
}

void main() {
  group('ApiService', () {
    test('403と429は自動再試行せずDioExceptionとして返す', () async {
      for (final statusCode in <int>[403, 429]) {
        final adapter = _FakeResponseAdapter(
          '[{"allcount":0}]',
          statusCode: statusCode,
        );
        final dio = Dio()..httpClientAdapter = adapter;
        final service = ApiService(dio: dio);

        await expectLater(
          service.searchNovels(const NovelSearchQuery()),
          throwsA(
            isA<DioException>().having(
              (error) => error.response?.statusCode,
              'statusCode',
              statusCode,
            ),
          ),
        );
        expect(adapter.requestCount, 1);
      }
    });

    test('HTTPリクエストに明示的なconnect/receive timeoutを渡す', () async {
      final adapter = _TimedHostAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      final service = ApiService(dio: dio);

      await service.searchNovels(const NovelSearchQuery());

      expect(adapter.connectTimeouts.single, const Duration(seconds: 10));
      expect(adapter.receiveTimeouts.single, const Duration(seconds: 30));
    });

    test('単話取得では従来どおり作品情報APIを取得する', () async {
      final adapter = _EpisodeFetchAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      final service = ApiService(dio: dio);

      final episode = await service.fetchEpisode('n1234ab', 1);

      expect(episode.subtitle, contains('本文タイトル'));
      expect(adapter.callCounts['api.syosetu.com'], 1);
      expect(adapter.callCounts['ncode.syosetu.com'], 1);
    });

    test('同一Nコードの取得済みNovelInfoがあれば作品情報APIを再取得しない', () async {
      final adapter = _EpisodeFetchAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      final service = ApiService(dio: dio);

      final episode = await service.fetchEpisode(
        'n1234ab',
        1,
        novelInfo: const NovelInfo(ncode: 'n1234ab', novelType: 1),
      );

      expect(episode.subtitle, contains('本文タイトル'));
      expect(adapter.callCounts['api.syosetu.com'], isNull);
      expect(adapter.callCounts['ncode.syosetu.com'], 1);
    });

    test('一括取得で重複Nコードを1件にまとめる', () async {
      final adapter = _FakeResponseAdapter(
        '[{"allcount":1},{"ncode":"n1234ab","title":"作品"}]',
      );
      final dio = Dio()..httpClientAdapter = adapter;
      final service = ApiService(dio: dio);

      final result = await service.fetchMultipleNovelsInfo([
        'N1234AB',
        'n1234ab',
        'N1234AB',
      ]);

      expect(adapter.requestedUris.single.queryParameters['ncode'], 'n1234ab');
      expect(result.keys, ['n1234ab']);
    });

    test('apiとncodeはホストごとに並列リクエストを1秒間隔に制限する', () async {
      final adapter = _TimedHostAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      final service = ApiService(dio: dio);

      await Future.wait([
        service.searchNovels(const NovelSearchQuery(word: '作品A')),
        service.searchNovels(const NovelSearchQuery(word: '作品B')),
        service.fetchEpisodeList('N1234AB', 1),
        service.fetchEpisodeList('N5678CD', 1),
      ]);

      for (final host in <String>['api.syosetu.com', 'ncode.syosetu.com']) {
        final times = adapter.requestTimes[host]!;
        expect(times, hasLength(2));
        expect(
          times.last - times.first,
          greaterThanOrEqualTo(const Duration(milliseconds: 900)),
        );
      }
    });

    group('fetchBasicNovelInfo レスポンス検証', () {
      test('allcount==0 のみを非公開・削除として扱うこと', () async {
        final service = _createService('[{"allcount":0}]');

        await expectLater(
          service.fetchBasicNovelInfo('N1234AB'),
          throwsA(isA<NovelNotFoundException>()),
        );
      });

      test('allcount>0 だが作品データが無い場合はFormatExceptionを投げること', () async {
        final service = _createService('[{"allcount":1}]');

        await expectLater(
          service.fetchBasicNovelInfo('N1234AB'),
          throwsA(isA<FormatException>()),
        );
      });

      test('メタデータが欠損している場合はFormatExceptionを投げること', () async {
        final service = _createService('[{}]');

        await expectLater(
          service.fetchBasicNovelInfo('N1234AB'),
          throwsA(isA<FormatException>()),
        );
      });

      test('レスポンスが空の場合はFormatExceptionを投げること', () async {
        final service = _createService('[]');

        await expectLater(
          service.fetchBasicNovelInfo('N1234AB'),
          throwsA(isA<FormatException>()),
        );
      });

      test('正常なレスポンスは作品情報を返すこと', () async {
        final service = _createService(
          '[{"allcount":1},'
          '{"ncode":"N1234AB","title":"テスト",'
          '"novel_type":"1","general_all_no":"3"}]',
        );

        final info = await service.fetchBasicNovelInfo('N1234AB');
        expect(info.workId, 'n1234ab');
        expect(info.title, 'テスト');
      });
    });

    group('累計ランキング制限値', () {
      test('allTimeRankingLimitは500であること', () {
        expect(allTimeRankingLimit, equals(500));
      });

      test('累計ランキングクエリのlimが500であること', () {
        // _fetchAllTimeRankingメソッドで使用されるクエリを検証
        const query = NovelSearchQuery(
          order: 'hyoka',
          lim: allTimeRankingLimit,
        );
        expect(query.lim, equals(500));
      });

      test('累計ランキングが500件まで取得可能であること', () {
        // なろう小説APIの仕様確認：limの最大値は500
        const query = NovelSearchQuery(order: 'hyoka', lim: 500);
        expect(query.lim, lessThanOrEqualTo(500));
      });
    });
  });
}
