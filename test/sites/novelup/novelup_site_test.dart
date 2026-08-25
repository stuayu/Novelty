import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/models/novel_info.dart';
import 'package:novelty/models/novel_search_query.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:novelty/sites/novelup/novelup_site.dart';
import 'package:novelty/utils/request_rate_limiter.dart';
import 'package:novelup_parser/novelup_parser.dart';

String _fixture(String name) =>
    File('test/fixtures/novelup/$name').readAsStringSync();

class _FixtureAdapter implements HttpClientAdapter {
  _FixtureAdapter(this.fixtures);

  final Map<String, ({String body, int status})> fixtures;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final uri = Uri.parse(options.path);
    final fixture = fixtures[uri.toString()] ?? fixtures[uri.path];
    if (fixture == null) {
      return ResponseBody.fromString('not found', 404);
    }
    return ResponseBody.fromString(
      fixture.body,
      fixture.status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['text/html; charset=utf-8'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _CountingRateLimiter extends RequestRateLimiter {
  _CountingRateLimiter() : super(interval: Duration.zero);

  int waitCount = 0;

  @override
  Future<void> wait() async {
    waitCount++;
  }
}

NovelupSite _createSite(
  _FixtureAdapter adapter, {
  RequestRateLimiter? rateLimiter,
}) {
  final dio = Dio()..httpClientAdapter = adapter;
  return NovelupSite(
    dio: dio,
    rateLimiter: rateLimiter ?? RequestRateLimiter(interval: Duration.zero),
  );
}

String _tocPage({
  required String workId,
  required int firstNumber,
  required int count,
  required int lastPage,
}) {
  final items = List<String>.generate(count, (offset) {
    final number = firstNumber + offset;
    return '''
      <div class="episodeListItem">
        <a class="episodeTitle"
           href="https://novelup.plus/story/$workId/${900000000 + number}"
           data-number="$number">第$number話</a>
        <div class="episodeDate"><p class="publishDate">26/8/25 7:07</p></div>
      </div>
    ''';
  }).join();
  return '''
    <p class="total_episode_num">総エピソード数：31話</p>
    <a href="https://novelup.plus/story/$workId?p=$lastPage">最後のページへ</a>
    $items
  ''';
}

void main() {
  group('NovelupSite', () {
    test('本文パーサ・表示情報・確定済みマスタデータを提供する', () {
      final site = NovelupSite(
        dio: Dio(),
        rateLimiter: RequestRateLimiter(interval: Duration.zero),
      );

      final content = site.parseEpisodeBody(_fixture('episode.html'));

      expect(site.source, NovelSource.novelup);
      expect(content.whereType<RubyText>(), hasLength(1));
      expect(
        site.metaText(const NovelInfo(source: NovelSource.novelup)),
        isNull,
      );
      expect(site.genres, hasLength(16));
      expect(site.genres.every((genre) => genre.bigGenreId == null), isTrue);
      expect(site.genres.every((genre) => !genre.isBigGenre), isTrue);
      expect(site.rankingTypes, hasLength(21));
      expect(
        site.rankingTypes.map((type) => type.id),
        containsAll(<String>['all', 'high-fantasy', 'nuponly', 'finished']),
      );
    });

    group('fetchNovelInfo', () {
      test('公開HTMLとJSON-LDから連載作品情報を返す', () async {
        final adapter = _FixtureAdapter(<String, ({String body, int status})>{
          '/story/258567814': (body: _fixture('serial_work.html'), status: 200),
        });

        final info = await _createSite(adapter).fetchNovelInfo('258567814');

        expect(info.source, NovelSource.novelup);
        expect(info.workId, '258567814');
        expect(info.ncode, isNull);
        expect(info.title, '筆を染める');
        expect(info.writer, '喜雨人');
        expect(info.userId, 150660268);
        expect(info.story, contains('小説の題材を探していた'));
        expect(info.genreId, '11');
        expect(info.novelType, 1);
        expect(info.end, 1);
        expect(info.generalAllNo, 2);
        expect(info.generalFirstup, '2026-08-25 00:00:00');
        expect(adapter.requests, hasLength(1));
      });

      test('HTTP 404の取得不能作品を明確な例外にする', () async {
        final adapter = _FixtureAdapter(<String, ({String body, int status})>{
          '/story/999999999': (body: 'ページが見つかりません', status: 404),
        });

        await expectLater(
          _createSite(adapter).fetchNovelInfo('999999999'),
          throwsA(isA<NovelupWorkNotFoundException>()),
        );
      });
    });

    group('fetchToc', () {
      test('30話ごとの全ページを取得し目次順の1始まり連番で返す', () async {
        final adapter = _FixtureAdapter(<String, ({String body, int status})>{
          '/story/819720642': (
            body: _tocPage(
              workId: '819720642',
              firstNumber: 1,
              count: 30,
              lastPage: 2,
            ),
            status: 200,
          ),
          'https://novelup.plus/story/819720642?p=2': (
            body: _tocPage(
              workId: '819720642',
              firstNumber: 31,
              count: 1,
              lastPage: 2,
            ),
            status: 200,
          ),
        });
        final limiter = _CountingRateLimiter();

        final episodes = await _createSite(
          adapter,
          rateLimiter: limiter,
        ).fetchToc('819720642');

        expect(episodes, hasLength(31));
        expect(
          episodes.map((episode) => episode.index),
          orderedEquals(<int>[
            for (var index = 1; index <= 31; index++) index,
          ]),
        );
        expect(episodes.first.source, NovelSource.novelup);
        expect(episodes.first.subtitle, '第1話');
        expect(
          episodes.first.url,
          'https://novelup.plus/story/819720642/900000001',
        );
        expect(episodes.last.subtitle, '第31話');
        expect(episodes.last.update, '26/8/25 7:07');
        expect(
          adapter.requests.map((request) => request.uri.toString()),
          <String>[
            'https://novelup.plus/story/819720642',
            'https://novelup.plus/story/819720642?p=2',
          ],
        );
        expect(limiter.waitCount, 2);
      });

      test('作品情報と目次で同じ作品HTMLをキャッシュ共有する', () async {
        final combined =
            '''
          ${_fixture('serial_work.html')}
          <div class="episodeListItem">
            <a class="episodeTitle"
               href="https://novelup.plus/story/258567814/492921017"
               data-number="1">プロローグ</a>
          </div>
        ''';
        final adapter = _FixtureAdapter(<String, ({String body, int status})>{
          '/story/258567814': (body: combined, status: 200),
        });
        final site = _createSite(adapter);

        await site.fetchNovelInfo('258567814');
        await site.fetchToc('258567814');

        expect(adapter.requests, hasLength(1));
      });
    });

    group('fetchEpisode', () {
      test('公開本文HTMLから話タイトルと本文を返す', () async {
        const episodeUrl = 'https://novelup.plus/story/258567814/492921017';
        final adapter = _FixtureAdapter(<String, ({String body, int status})>{
          '/story/258567814/492921017': (
            body: _fixture('episode.html'),
            status: 200,
          ),
        });

        final episode = await _createSite(
          adapter,
        ).fetchEpisode('258567814', 1, url: episodeUrl);

        expect(episode.source, NovelSource.novelup);
        expect(episode.index, 1);
        expect(episode.subtitle, 'プロローグ');
        expect(episode.url, episodeUrl);
        expect(episode.body, contains('id="episode_content"'));
        expect(adapter.requests, hasLength(1));
      });

      test('別作品と公式外の本文URLはHTTPリクエスト前に拒否する', () async {
        final adapter = _FixtureAdapter(
          <String, ({String body, int status})>{},
        );
        final site = _createSite(adapter);

        for (final url in <String>[
          'https://novelup.plus/story/999999999/492921017',
          'https://example.com/story/258567814/492921017',
          'https://novelup.plus/api/story/258567814/492921017',
        ]) {
          await expectLater(
            site.fetchEpisode('258567814', 1, url: url),
            throwsA(anyOf(isA<FormatException>(), isA<StateError>())),
          );
        }
        expect(adapter.requests, isEmpty);
      });
    });

    group('fetchRanking', () {
      test('全21ランキング種別を対応URLから作品情報として取得できる', () async {
        final seedSite = NovelupSite(
          dio: Dio(),
          rateLimiter: RequestRateLimiter(interval: Duration.zero),
        );
        final fixtures = <String, ({String body, int status})>{
          for (final type in seedSite.rankingTypes)
            type.urlPath: (body: _fixture('ranking_page.html'), status: 200),
        };
        final adapter = _FixtureAdapter(fixtures);
        final site = _createSite(adapter);

        for (final type in site.rankingTypes) {
          final page = await site.fetchRanking(type.id);

          expect(page.novels, hasLength(1));
          expect(page.hasNextPage, isFalse);
          final info = page.novels.single;
          expect(info.source, NovelSource.novelup);
          expect(info.workId, '780020941');
          expect(info.ncode, isNull);
          expect(info.title, 'マリオネットは眠らない');
          expect(info.writer, 'いのり');
          expect(info.genreId, '1');
          expect(info.novelType, 2);
          expect(info.end, 0);
          expect(info.generalAllNo, 1);
          expect(info.totalCharacterCount, 2318);
          expect(info.generalLastup, '2026-08-25 00:00:00');
        }
        expect(adapter.requests, hasLength(21));
      });

      test('2ページ目をp=2で取得する', () async {
        final adapter = _FixtureAdapter(<String, ({String body, int status})>{
          'https://novelup.plus/ranking/all/day?p=2': (
            body: _fixture('ranking_page.html'),
            status: 200,
          ),
        });

        final page = await _createSite(adapter).fetchRanking('all', page: 2);

        expect(page.novels, hasLength(1));
        expect(page.hasNextPage, isFalse);
        expect(
          adapter.requests.single.uri.toString(),
          'https://novelup.plus/ranking/all/day?p=2',
        );
      });
    });

    group('searchNovels', () {
      test('確定済み検索パラメータと結果DOMから作品一覧を返す', () async {
        final adapter = _FixtureAdapter(<String, ({String body, int status})>{
          '/search': (body: _fixture('search_page.html'), status: 200),
        });

        final result = await _createSite(adapter).searchNovels(
          const NovelSearchQuery(
            source: NovelSource.novelup,
            word: '異世界',
            genreId: <String>['1'],
            st: 31,
          ),
        );

        expect(result.allCount, 8478);
        expect(result.novels, hasLength(1));
        final info = result.novels.single;
        expect(info.source, NovelSource.novelup);
        expect(info.workId, '324212690');
        expect(info.title, '弱小領主のダメ息子、伝説の竜姫を召喚する。');
        expect(info.writer, 'tmk');
        expect(info.genreId, '1');
        expect(info.novelType, 1);
        expect(info.generalAllNo, 196);
        expect(info.totalCharacterCount, 456655);
        final query = adapter.requests.single.uri.queryParameters;
        expect(query['q'], '異世界');
        expect(query['sort'], '1');
        expect(query['genre[1]'], '1');
        expect(query['p'], '2');
      });
    });
  });
}
