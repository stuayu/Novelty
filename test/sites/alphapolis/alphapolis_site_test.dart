import 'dart:io';
import 'dart:typed_data';

import 'package:alphapolis_parser/alphapolis_parser.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/models/novel_info.dart';
import 'package:novelty/models/novel_search_query.dart';
import 'package:novelty/sites/alphapolis/alphapolis_site.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:novelty/utils/request_rate_limiter.dart';

String _fixture(String name) =>
    File('test/fixtures/alphapolis/$name').readAsStringSync();

class _FixtureAdapter implements HttpClientAdapter {
  _FixtureAdapter(
    this.fixtures, {
    this.statusCodes = const <String, int>{},
    this.responseHeaders = const <String, Map<String, List<String>>>{},
  });

  final Map<String, String> fixtures;
  final Map<String, int> statusCodes;
  final Map<String, Map<String, List<String>>> responseHeaders;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final path = Uri.parse(options.path).path;
    final key = '${options.method} $path';
    final body = fixtures[key] ?? fixtures[path];
    if (body == null) {
      return ResponseBody.fromString('not found', 404);
    }
    return ResponseBody.fromString(
      body,
      statusCodes[key] ?? statusCodes[path] ?? 200,
      headers:
          responseHeaders[key] ??
          responseHeaders[path] ??
          <String, List<String>>{
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

const String _episodePage = r'''
<h2 class="p-novel-episode__episode-title">第1話「数字にならない男」</h2>
<div id="novelBody" class="p-novel-episode__text"></div>
<script>
$.ajaxSetup({headers: {"X-CSRF-TOKEN": "csrf-token-value"}});
$('div#novelBody').load('/novel/episode_body', {
  'episode': '11502116',
  'token': '0123456789abcdef0123456789abcdef'
});
</script>
''';

AlphapolisSite _createSite(_FixtureAdapter adapter) {
  final dio = Dio()..httpClientAdapter = adapter;
  return AlphapolisSite(
    dio: dio,
    rateLimiter: RequestRateLimiter(interval: Duration.zero),
  );
}

void main() {
  group('AlphapolisSite', () {
    test('本文パーサ・メタ情報・マスタデータを提供する', () {
      final site = AlphapolisSite(
        dio: Dio(),
        rateLimiter: RequestRateLimiter(interval: Duration.zero),
      );

      final content = site.parseEpisodeBody(_fixture('ruby_episode_body.html'));

      expect(site.source, NovelSource.alphapolis);
      expect(content.whereType<RubyText>(), hasLength(2));
      expect(
        site.metaText(
          const NovelInfo(source: NovelSource.alphapolis, allPoint: 5631),
        ),
        '5,631 pt',
      );
      expect(site.genres, hasLength(16));
      expect(site.genres.first.id, '110100');
      expect(site.genres.every((genre) => !genre.isBigGenre), isTrue);
      expect(site.rankingTypes, hasLength(12));
      expect(
        site.rankingTypes.map((type) => type.id),
        containsAll(<String>['completed', '24hpt', 'weekly', 'episode_old']),
      );
    });

    group('fetchNovelInfo', () {
      test('app-cover-dataと作品DOMから連載作品情報を返す', () async {
        final adapter = _FixtureAdapter(<String, String>{
          '/novel/480761512/519070183': _fixture('serial_work.html'),
        });
        final site = _createSite(adapter);

        final info = await site.fetchNovelInfo('480761512-519070183');

        expect(info.source, NovelSource.alphapolis);
        expect(info.workId, '480761512-519070183');
        expect(info.ncode, isNull);
        expect(info.title, startsWith('妹の入院費のため'));
        expect(info.writer, 'さくらろ');
        expect(info.story, contains('大手クラン・ゼノギア'));
        expect(info.genreId, '110400');
        expect(info.end, 1);
        expect(info.novelType, 1);
        expect(info.generalAllNo, 2);
        expect(info.allPoint, 5631);
        expect(info.followCount, 34291);
        expect(info.keyword, '現代ダンジョン');
        expect(info.generalFirstup, '2026-07-12 07:20:00');
        expect(info.generalLastup, '2026-08-24 20:00:00');
      });

      test('1話完結作品を短編・完結として返す', () async {
        final adapter = _FixtureAdapter(<String, String>{
          '/novel/600144500/873826540': _fixture('short_work.html'),
        });
        final site = _createSite(adapter);

        final info = await site.fetchNovelInfo('600144500-873826540');

        expect(info.end, 0);
        expect(info.novelType, 2);
        expect(info.generalAllNo, 1);
        expect(info.totalCharacterCount, 10256);
      });

      test('app-cover-dataが無い作品ページはFormatExceptionを投げる', () async {
        final adapter = _FixtureAdapter(<String, String>{
          '/novel/480761512/519070183': '<html></html>',
        });

        await expectLater(
          _createSite(adapter).fetchNovelInfo('480761512-519070183'),
          throwsA(isA<FormatException>()),
        );
      });
    });

    group('fetchToc', () {
      test('chapterEpisodesの全話を目次順の1始まり連番で返す', () async {
        final adapter = _FixtureAdapter(<String, String>{
          '/novel/480761512/519070183': _fixture('toc.html'),
        });
        final site = _createSite(adapter);

        final episodes = await site.fetchToc('480761512-519070183');

        expect(episodes, hasLength(2));
        expect(episodes.map((episode) => episode.index), <int?>[1, 2]);
        expect(episodes.first.source, NovelSource.alphapolis);
        expect(episodes.first.subtitle, '第1話「数字にならない男」');
        expect(
          episodes.first.url,
          'https://www.alphapolis.co.jp/novel/480761512/519070183/'
          'episode/11502116',
        );
        expect(episodes.first.update, '2026-07-12 07:20:00');
      });

      test('chapterEpisodesが無い作品ページはFormatExceptionを投げる', () async {
        final adapter = _FixtureAdapter(<String, String>{
          '/novel/480761512/519070183':
              '<script id="app-cover-data">{"content":{}}</script>',
        });

        await expectLater(
          _createSite(adapter).fetchToc('480761512-519070183'),
          throwsA(isA<FormatException>()),
        );
      });
    });

    group('fetchEpisode', () {
      test('GETのCookie・CSRF・tokenを本文POSTへ載せて本文を返す', () async {
        final adapter = _FixtureAdapter(
          <String, String>{
            'GET /novel/480761512/519070183/episode/11502116': _episodePage,
            'POST /novel/episode_body': _fixture('ruby_episode_body.html'),
          },
          responseHeaders: <String, Map<String, List<String>>>{
            'GET /novel/480761512/519070183/episode/11502116':
                <String, List<String>>{
                  Headers.contentTypeHeader: <String>[
                    'text/html; charset=utf-8',
                  ],
                  'set-cookie': <String>[
                    'XSRF-TOKEN=cookie-token; Path=/; Secure',
                    'alphapolis_session=session-value; Path=/; HttpOnly',
                  ],
                },
          },
        );
        final limiter = _CountingRateLimiter();
        final dio = Dio()..httpClientAdapter = adapter;
        final site = AlphapolisSite(dio: dio, rateLimiter: limiter);
        const episodeUrl =
            'https://www.alphapolis.co.jp/novel/480761512/519070183/'
            'episode/11502116';

        final episode = await site.fetchEpisode(
          '480761512-519070183',
          1,
          url: episodeUrl,
        );

        expect(episode.source, NovelSource.alphapolis);
        expect(episode.index, 1);
        expect(episode.subtitle, '第1話「数字にならない男」');
        expect(episode.url, episodeUrl);
        expect(episode.body, contains('<ruby>王族'));
        expect(adapter.requests, hasLength(2));
        final post = adapter.requests.last;
        expect(post.method, 'POST');
        expect(post.headers['X-CSRF-TOKEN'], 'csrf-token-value');
        expect(post.headers['Referer'], episodeUrl);
        expect(post.headers['X-Requested-With'], 'XMLHttpRequest');
        expect(
          post.headers[Headers.contentTypeHeader],
          'application/x-www-form-urlencoded; charset=UTF-8',
        );
        expect(post.headers['Cookie'], contains('XSRF-TOKEN=cookie-token'));
        expect(
          post.headers['Cookie'],
          contains('alphapolis_session=session-value'),
        );
        expect(post.data.toString(), contains('episode=11502116'));
        expect(
          post.data.toString(),
          contains('token=0123456789abcdef0123456789abcdef'),
        );
        expect(limiter.waitCount, 2);
      });

      test('CSRF不一致の419を明確なHTTP例外にする', () async {
        final adapter = _FixtureAdapter(
          <String, String>{
            'GET /novel/480761512/519070183/episode/11502116': _episodePage,
            'POST /novel/episode_body': '{"message":"CSRF token mismatch."}',
          },
          statusCodes: const <String, int>{'POST /novel/episode_body': 419},
        );

        await expectLater(
          _createSite(adapter).fetchEpisode(
            '480761512-519070183',
            1,
            url:
                'https://www.alphapolis.co.jp/novel/480761512/519070183/'
                'episode/11502116',
          ),
          throwsA(
            isA<AlphapolisHttpException>().having(
              (error) => error.statusCode,
              'statusCode',
              419,
            ),
          ),
        );
      });

      test('レンタル非公開話の403を明確なHTTP例外にする', () async {
        final adapter = _FixtureAdapter(
          <String, String>{
            'GET /novel/480761512/519070183/episode/11502116': _fixture(
              'rental_denied.html',
            ),
          },
          statusCodes: const <String, int>{
            'GET /novel/480761512/519070183/episode/11502116': 403,
          },
        );

        await expectLater(
          _createSite(adapter).fetchEpisode(
            '480761512-519070183',
            1,
            url:
                'https://www.alphapolis.co.jp/novel/480761512/519070183/'
                'episode/11502116',
          ),
          throwsA(
            isA<AlphapolisHttpException>().having(
              (error) => error.statusCode,
              'statusCode',
              403,
            ),
          ),
        );
      });

      test('公式外URLとrobots.txt禁止URLはHTTPリクエスト前に拒否する', () async {
        final adapter = _FixtureAdapter(<String, String>{});
        final site = _createSite(adapter);

        for (final url in <String>[
          'https://example.com/novel/480761512/519070183/episode/11502116',
          'https://www.alphapolis.co.jp/dreambookclub/private',
        ]) {
          await expectLater(
            site.fetchEpisode('480761512-519070183', 1, url: url),
            throwsStateError,
          );
        }
        expect(adapter.requests, isEmpty);
      });
    });

    group('searchNovels', () {
      test('検索結果DOMから作品一覧と総件数を返す', () async {
        final adapter = _FixtureAdapter(<String, String>{
          '/search': _fixture('search_page.html'),
        });

        final result = await _createSite(adapter).searchNovels(
          const NovelSearchQuery(
            source: NovelSource.alphapolis,
            word: '異世界',
          ),
        );

        expect(result.allCount, 63271);
        expect(result.novels, hasLength(1));
        final first = result.novels.first;
        expect(first.source, NovelSource.alphapolis);
        expect(first.workId, '386971645-725078791');
        expect(first.title, '私より王女殿下が好きなら別れましょう');
        expect(first.writer, '天宮有');
        expect(first.story, 'あらすじ抜粋');
        expect(first.allPoint, 118833);
        expect(first.totalCharacterCount, 12635);
        expect(first.generalLastup, '2026-08-24');
        final uri = Uri.parse(adapter.requests.single.path);
        expect(uri.queryParameters['query'], '異世界');
        expect(uri.queryParameters['category'], 'novel');
      });

      test('stをpageへ変換し、ジャンルは共通genreIdだけを使う', () async {
        final adapter = _FixtureAdapter(<String, String>{
          '/search': _fixture('search_page.html'),
        });

        await _createSite(adapter).searchNovels(
          const NovelSearchQuery(
            source: NovelSource.alphapolis,
            word: '異世界',
            genreId: <String>['110400'],
            st: 41,
          ),
        );

        final query = Uri.parse(adapter.requests.single.path).queryParameters;
        expect(query['page'], '3');
        expect(query['category_ids'], '110400');
        expect(query, isNot(contains('serial_status')));
      });

      test('検索結果DOMが無い場合はFormatExceptionを投げる', () async {
        final adapter = _FixtureAdapter(<String, String>{
          '/search': '<html></html>',
        });

        await expectLater(
          _createSite(adapter).searchNovels(
            const NovelSearchQuery(
              source: NovelSource.alphapolis,
              word: '異世界',
            ),
          ),
          throwsA(isA<FormatException>()),
        );
      });
    });

    group('fetchRanking', () {
      test('作品一覧DOMからランキングと次ページ有無を返す', () async {
        final adapter = _FixtureAdapter(<String, String>{
          '/novel/index': _fixture('ranking_page.html'),
        });

        final ranking = await _createSite(adapter).fetchRanking('24hpt');

        expect(ranking.hasNextPage, isTrue);
        expect(ranking.novels, hasLength(1));
        final first = ranking.novels.first;
        expect(first.source, NovelSource.alphapolis);
        expect(first.workId, '480761512-519070183');
        expect(first.genreId, '110400');
        expect(first.end, 1);
        expect(first.allPoint, 5631);
        final query = Uri.parse(adapter.requests.single.path).queryParameters;
        expect(query['sort'], '24hpt');
      });

      test('pageをURLへ反映し、最終ページではhasNextPage=false', () async {
        final adapter = _FixtureAdapter(<String, String>{
          '/novel/index': _fixture('ranking_page.html'),
        });

        final ranking = await _createSite(adapter).fetchRanking(
          'total',
          page: 1343,
        );

        expect(ranking.hasNextPage, isFalse);
        final query = Uri.parse(adapter.requests.single.path).queryParameters;
        expect(query['sort'], 'total');
        expect(query['page'], '1343');
      });

      test('未定義のsort値はHTTPリクエスト前に拒否する', () async {
        final adapter = _FixtureAdapter(<String, String>{});

        await expectLater(
          _createSite(adapter).fetchRanking('unknown'),
          throwsArgumentError,
        );
        expect(adapter.requests, isEmpty);
      });
    });
  });
}
