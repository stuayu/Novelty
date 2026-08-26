import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:estar_parser/estar_parser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/models/novel_info.dart';
import 'package:novelty/models/novel_search_query.dart';
import 'package:novelty/sites/estar/estar_site.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:novelty/utils/request_rate_limiter.dart';

String _fixture(String name) =>
    File('test/fixtures/estar/$name').readAsStringSync();

const _guestCookieHeaders = <String, List<String>>{
  'set-cookie': <String>[
    'guestinfo=guest-value; Path=/; Secure',
    'requestor_id=requestor-value; Path=/; Secure',
  ],
};

String _graphqlEpisodeResponse({
  required bool payRequired,
  required String status,
  String body = '公開本文',
}) => jsonEncode(<String, dynamic>{
  'data': <String, dynamic>{
    'novel': <String, dynamic>{
      'pages': <String, dynamic>{
        'nodes': <Map<String, dynamic>>[
          <String, dynamic>{
            'episodeNo': 2,
            'pageNo': 3,
            'pageNoInEpisode': 1,
            'pageCountInEpisode': 1,
            'title': '冷たい人',
            'body': body,
            'status': status,
            'payRequired': payRequired,
          },
        ],
      },
    },
  },
});

class _FixtureResponse {
  const _FixtureResponse(
    this.body, {
    this.statusCode = 200,
    this.headers = const <String, List<String>>{},
  });

  final String body;
  final int statusCode;
  final Map<String, List<String>> headers;
}

class _FixtureAdapter implements HttpClientAdapter {
  _FixtureAdapter(this.responses);

  final Map<String, _FixtureResponse> responses;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final response =
        responses['${options.method} ${options.uri}'] ??
        responses['${options.method} ${options.uri.path}'];
    if (response == null) {
      return ResponseBody.fromString('not found', 404);
    }
    return ResponseBody.fromString(
      response.body,
      response.statusCode,
      headers: response.headers,
    );
  }

  @override
  void close({bool force = false}) {}
}

class _PagingFixtureAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (options.method == 'GET') {
      return ResponseBody.fromString(
        '<html></html>',
        200,
        headers: _guestCookieHeaders,
      );
    }
    final data = options.data as Map<String, dynamic>;
    final variables = data['data'] as Map<String, dynamic>;
    final pageNoAfter = variables['pageNoAfter'] as int;
    final pageNumbers = pageNoAfter == 1
        ? List<int>.generate(15, (index) => index + 1)
        : <int>[16];
    final body = jsonEncode(<String, dynamic>{
      'data': <String, dynamic>{
        'novel': <String, dynamic>{
          'pages': <String, dynamic>{
            'nodes': pageNumbers
                .map(
                  (pageNo) => <String, dynamic>{
                    'episodeNo': 1,
                    'pageNo': pageNo,
                    'pageNoInEpisode': pageNo,
                    'pageCountInEpisode': 16,
                    'title': pageNo == 1 ? '長編話' : null,
                    'body': '本文$pageNo',
                    'status': 'published',
                    'payRequired': false,
                  },
                )
                .toList(),
          },
        },
      },
    });
    return ResponseBody.fromString(body, 200);
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

EstarSite _createSite(
  _FixtureAdapter adapter, {
  RequestRateLimiter? rateLimiter,
}) {
  final dio = Dio()..httpClientAdapter = adapter;
  return EstarSite(
    dio: dio,
    rateLimiter: rateLimiter ?? RequestRateLimiter(interval: Duration.zero),
  );
}

void main() {
  group('EstarSite', () {
    test('本文パーサ・確定済みジャンル・ランキング種別を提供する', () {
      final site = EstarSite(
        dio: Dio(),
        rateLimiter: RequestRateLimiter(interval: Duration.zero),
      );

      final content = site.parseEpisodeBody('|黛彩葉《まゆずみいろは》');

      expect(site.source, NovelSource.estar);
      expect(content.single, isA<RubyText>());
      expect(site.genres, hasLength(16));
      expect(site.genres.map((genre) => genre.id), contains('1020'));
      expect(site.genres.every((genre) => genre.bigGenreId == null), isTrue);
      expect(site.genres.every((genre) => !genre.isBigGenre), isTrue);
      expect(
        site.rankingTypes
            .map((type) => (type.id, type.label, type.urlPath))
            .toList(),
        <(String, String, String)>[
          (
            'all',
            '総合',
            '/novels/ranking?ranking_type=all&ranking_axis_type=general_popular',
          ),
          (
            'kiriban',
            'スター',
            '/novels/kiriban?ranking_type=all&ranking_axis_type=general_popular',
          ),
          (
            'new_arrivals',
            '新着',
            '/novels/new_arrivals?ranking_type=all&ranking_axis_type=general_popular&type=pickup',
          ),
          (
            'finished',
            '完結',
            '/novels/finished?ranking_type=all&ranking_axis_type=general_popular&type=pickup',
          ),
          (
            'trend',
            'トレンド',
            '/novels/trend?ranking_type=all&ranking_axis_type=general',
          ),
        ],
      );
      expect(
        site.metaText(const NovelInfo(source: NovelSource.estar)),
        isNull,
      );
    });

    group('fetchNovelInfo', () {
      test('__NUXT_DATA__と公開DOMから連載作品情報を返す', () async {
        final adapter = _FixtureAdapter(<String, _FixtureResponse>{
          'GET /novels/26544596': _FixtureResponse(
            _fixture('serial_work.html'),
          ),
        });

        final info = await _createSite(adapter).fetchNovelInfo('26544596');

        expect(info.source, NovelSource.estar);
        expect(info.workId, '26544596');
        expect(info.ncode, isNull);
        expect(info.title, '交際0日婚したはずなのに冷徹夫からの溺愛がとまりません');
        expect(info.writer, '春野カノン🌻コミカライズ配信中');
        expect(info.story, contains('冷徹夫との新婚生活'));
        expect(info.genreId, '1020');
        expect(info.novelType, 1);
        expect(info.end, 1);
        expect(info.generalAllNo, 34);
        expect(info.totalCharacterCount, 74837);
        expect(info.generalLastup, '2026-08-25 07:00:16');
        expect(adapter.requests, hasLength(1));
      });

      test('1話の完結作品を短編として返す', () async {
        final adapter = _FixtureAdapter(<String, _FixtureResponse>{
          'GET /novels/594': _FixtureResponse(_fixture('short_work.html')),
        });

        final info = await _createSite(adapter).fetchNovelInfo('594');

        expect(info.ncode, isNull);
        expect(info.title, 'アンタとアタシ');
        expect(info.story, '珍しく恋愛モノ');
        expect(info.genreId, '1020');
        expect(info.novelType, 2);
        expect(info.end, 0);
        expect(info.generalAllNo, 1);
        expect(info.totalCharacterCount, 741);
        expect(info.generalLastup, '2007-03-09 21:20:18');
      });

      test('HTTPエラーをステータスコード付き例外にする', () async {
        final adapter = _FixtureAdapter(<String, _FixtureResponse>{
          'GET /novels/999': const _FixtureResponse(
            'not found',
            statusCode: 404,
          ),
        });

        await expectLater(
          _createSite(adapter).fetchNovelInfo('999'),
          throwsA(
            isA<EstarHttpException>().having(
              (error) => error.statusCode,
              'statusCode',
              404,
            ),
          ),
        );
      });
    });

    group('fetchToc', () {
      test('__NUXT_DATA__の目次を1始まり連番と開始ページURLへ変換する', () async {
        final adapter = _FixtureAdapter(<String, _FixtureResponse>{
          'GET /novels/26544596': _FixtureResponse(_fixture('toc.html')),
        });

        final episodes = await _createSite(adapter).fetchToc('26544596');

        expect(episodes, hasLength(3));
        expect(episodes.map((episode) => episode.index), <int?>[1, 2, 3]);
        expect(episodes.first.source, NovelSource.estar);
        expect(episodes.first.subtitle, 'プロローグ');
        expect(
          episodes.first.url,
          'https://estar.jp/novels/26544596/viewer?page=1',
        );
        expect(episodes.last.subtitle, '九十九家の妻');
        expect(
          episodes.last.url,
          'https://estar.jp/novels/26544596/viewer?page=13',
        );
      });

      test('100話超は未確認のページングを推測せず明確な例外にする', () async {
        final adapter = _FixtureAdapter(<String, _FixtureResponse>{
          'GET /novels/123': const _FixtureResponse('''
            <script id="__NUXT_DATA__" type="application/json">
              {"episodeCount":101,"episodes":[{"title":"第1話","pageNo":1}]}
            </script>
          '''),
        });

        await expectLater(
          _createSite(adapter).fetchToc('123'),
          throwsA(isA<EstarTocLimitException>()),
        );
      });
    });

    group('fetchEpisode', () {
      test('公開GETのCookieを付けて15ページ単位のGraphQL本文を取得する', () async {
        const episodeUrl = 'https://estar.jp/novels/26544596/viewer?page=3';
        final adapter = _FixtureAdapter(<String, _FixtureResponse>{
          'GET $episodeUrl': const _FixtureResponse(
            '<html><title>viewer</title></html>',
            headers: _guestCookieHeaders,
          ),
          'POST /api/graphql': _FixtureResponse(_fixture('episode.html')),
        });
        final limiter = _CountingRateLimiter();

        final episode = await _createSite(
          adapter,
          rateLimiter: limiter,
        ).fetchEpisode('26544596', 2, url: episodeUrl);

        expect(episode.source, NovelSource.estar);
        expect(episode.index, 2);
        expect(episode.url, episodeUrl);
        expect(episode.body, contains('時は遡り数ヶ月前の五月。'));
        expect(episode.body, contains('\n|黛彩葉《まゆずみいろは》'));
        expect(episode.body, isNot(contains(r'\n')));
        expect(episode.body, contains('|黛彩葉《まゆずみいろは》'));
        expect(adapter.requests, hasLength(2));
        expect(limiter.waitCount, 2);

        final post = adapter.requests.last;
        expect(post.method, 'POST');
        expect(post.uri.toString(), 'https://estar.jp/api/graphql');
        expect(
          post.headers['Cookie'],
          'guestinfo=guest-value; requestor_id=requestor-value',
        );
        expect(post.headers['x-from'], episodeUrl);
        expect(post.data, <String, dynamic>{
          'query': 'pages/novels/workId/viewer/nextNovelPages',
          'data': <String, dynamic>{
            'workId': '26544596',
            'first': 15,
            'pageNoAfter': 3,
            'path': '/novels/26544596/viewer',
          },
          'fragments': <String>['novelPageInViewer'],
        });
      });

      test('15ページを超える話はpageNoAfterを更新して全ページを取得する', () async {
        const episodeUrl = 'https://estar.jp/novels/26544596/viewer?page=1';
        final adapter = _PagingFixtureAdapter();
        final dio = Dio()..httpClientAdapter = adapter;

        final episode = await EstarSite(
          dio: dio,
          rateLimiter: RequestRateLimiter(interval: Duration.zero),
        ).fetchEpisode('26544596', 1, url: episodeUrl);

        expect(episode.subtitle, '長編話');
        expect(episode.body, startsWith('本文1\n本文2'));
        expect(episode.body, endsWith('本文16'));
        expect(adapter.requests, hasLength(3));
        expect(
          adapter.requests
              .where((request) => request.method == 'POST')
              .map(
                (request) =>
                    ((request.data as Map<String, dynamic>)['data']
                        as Map<String, dynamic>)['pageNoAfter'],
              ),
          <int>[1, 16],
        );
      });

      test('有料話を空本文として成功扱いせず明確な例外にする', () async {
        const episodeUrl = 'https://estar.jp/novels/26544596/viewer?page=3';
        final adapter = _FixtureAdapter(<String, _FixtureResponse>{
          'GET $episodeUrl': const _FixtureResponse(
            '<html></html>',
            headers: _guestCookieHeaders,
          ),
          'POST /api/graphql': _FixtureResponse(
            _graphqlEpisodeResponse(
              payRequired: true,
              status: 'published',
              body: '',
            ),
          ),
        });

        await expectLater(
          _createSite(adapter).fetchEpisode(
            '26544596',
            2,
            url: episodeUrl,
          ),
          throwsA(isA<EstarPaidEpisodeException>()),
        );
      });

      test('非公開話を空本文として成功扱いせず公開状態付き例外にする', () async {
        const episodeUrl = 'https://estar.jp/novels/26544596/viewer?page=3';
        final adapter = _FixtureAdapter(<String, _FixtureResponse>{
          'GET $episodeUrl': const _FixtureResponse(
            '<html></html>',
            headers: _guestCookieHeaders,
          ),
          'POST /api/graphql': _FixtureResponse(
            _graphqlEpisodeResponse(
              payRequired: false,
              status: 'draft',
              body: '',
            ),
          ),
        });

        await expectLater(
          _createSite(adapter).fetchEpisode(
            '26544596',
            2,
            url: episodeUrl,
          ),
          throwsA(
            isA<EstarUnavailableEpisodeException>().having(
              (error) => error.status,
              'status',
              'draft',
            ),
          ),
        );
      });

      test('guestinfoかrequestor_idが無ければGraphQLを送信しない', () async {
        const episodeUrl = 'https://estar.jp/novels/26544596/viewer?page=3';
        final adapter = _FixtureAdapter(<String, _FixtureResponse>{
          'GET $episodeUrl': const _FixtureResponse(
            '<html></html>',
            headers: <String, List<String>>{
              'set-cookie': <String>['guestinfo=guest-value; Path=/'],
            },
          ),
        });

        await expectLater(
          _createSite(adapter).fetchEpisode(
            '26544596',
            2,
            url: episodeUrl,
          ),
          throwsA(isA<EstarGuestCookieException>()),
        );
        expect(adapter.requests, hasLength(1));
      });

      test('公式外URLは公開範囲外としてHTTP送信前に拒否する', () async {
        final adapter = _FixtureAdapter(<String, _FixtureResponse>{});

        await expectLater(
          _createSite(adapter).fetchEpisode(
            '26544596',
            2,
            url: 'https://example.com/novels/26544596/viewer?page=3',
          ),
          throwsStateError,
        );
        expect(adapter.requests, isEmpty);
      });
    });

    group('fetchRanking', () {
      test('全5種別を定義済みURLから取得しSSRの順位順で作品情報を返す', () async {
        final seedSite = EstarSite(
          dio: Dio(),
          rateLimiter: RequestRateLimiter(interval: Duration.zero),
        );
        final adapter = _FixtureAdapter(<String, _FixtureResponse>{
          for (final type in seedSite.rankingTypes)
            'GET https://estar.jp${type.urlPath}': _FixtureResponse(
              _fixture('ranking_page.html'),
            ),
        });
        final limiter = _CountingRateLimiter();
        final site = _createSite(adapter, rateLimiter: limiter);

        for (final type in site.rankingTypes) {
          final result = await site.fetchRanking(type.id);

          expect(result.hasNextPage, isTrue);
          expect(result.novels, hasLength(1));
          final firstPlace = result.novels.first;
          expect(firstPlace.source, NovelSource.estar);
          expect(firstPlace.workId, '26544596');
          expect(firstPlace.ncode, isNull);
          expect(
            firstPlace.title,
            '交際0日婚したはずなのに冷徹夫からの溺愛がとまりません',
          );
          expect(firstPlace.writer, '春野カノン🌻コミカライズ配信中');
          expect(firstPlace.story, contains('黛彩葉'));
          expect(firstPlace.genreId, '1020');
          expect(firstPlace.keyword, contains('交際0日婚'));
          expect(firstPlace.end, 1);
          expect(firstPlace.novelType, isNull);
          expect(firstPlace.generalLastup, '2026-08-26 07:00:17');
        }

        expect(adapter.requests, hasLength(5));
        expect(limiter.waitCount, 5);
      });

      test('2ページ目は既存クエリを保持してpage=2を追加する', () async {
        const url =
            'https://estar.jp/novels/ranking?ranking_type=all&ranking_axis_type=general_popular&page=2';
        final adapter = _FixtureAdapter(<String, _FixtureResponse>{
          'GET $url': _FixtureResponse(_fixture('ranking_page.html')),
        });

        final result = await _createSite(adapter).fetchRanking('all', page: 2);

        expect(result.hasNextPage, isTrue);
        expect(adapter.requests.single.uri.toString(), url);
      });

      test('未定義種別と1未満のページはHTTP送信前に拒否する', () async {
        final adapter = _FixtureAdapter(<String, _FixtureResponse>{});
        final site = _createSite(adapter);

        await expectLater(
          site.fetchRanking('unknown'),
          throwsArgumentError,
        );
        await expectLater(
          site.fetchRanking('all', page: 0),
          throwsArgumentError,
        );
        expect(adapter.requests, isEmpty);
      });

      test('SSRにランキング作品が無ければ空成功にしない', () async {
        final adapter = _FixtureAdapter(<String, _FixtureResponse>{
          'GET /novels/ranking': const _FixtureResponse('''
            <script id="__NUXT_DATA__" type="application/json">
              {"pageInfo":{"hasNextPage":false},"nodes":[]}
            </script>
          '''),
        });

        await expectLater(
          _createSite(adapter).fetchRanking('all'),
          throwsFormatException,
        );
      });
    });

    group('searchNovels', () {
      test('keywordとst由来のpageを送りSSR検索結果を返す', () async {
        const url = 'https://estar.jp/novels?keyword=%E6%81%8B%E6%84%9B&page=2';
        final adapter = _FixtureAdapter(<String, _FixtureResponse>{
          'GET $url': _FixtureResponse(_fixture('search_page.html')),
        });
        final limiter = _CountingRateLimiter();

        final result =
            await _createSite(
              adapter,
              rateLimiter: limiter,
            ).searchNovels(
              const NovelSearchQuery(
                source: NovelSource.estar,
                word: ' 恋愛 ',
                st: 31,
              ),
            );

        expect(result.allCount, 795);
        expect(result.novels, hasLength(1));
        final info = result.novels.single;
        expect(info.source, NovelSource.estar);
        expect(info.workId, '9736231');
        expect(info.ncode, isNull);
        expect(info.title, 'ペットと彼氏と三角関係');
        expect(info.writer, 'suiren');
        expect(info.story, '年上の彼氏と年下のペットと三角関係');
        expect(info.genreId, '1020');
        expect(info.end, 0);
        expect(info.novelType, isNull);
        expect(info.totalCharacterCount, 72118);
        expect(info.generalLastup, '2026-08-21 21:58:59');
        expect(adapter.requests.single.uri.toString(), url);
        expect(limiter.waitCount, 1);
      });

      test('未確定のジャンル指定は無視せずHTTP送信前に非対応とする', () async {
        final adapter = _FixtureAdapter(<String, _FixtureResponse>{});

        await expectLater(
          _createSite(adapter).searchNovels(
            const NovelSearchQuery(
              source: NovelSource.estar,
              word: '恋愛',
              genreId: <String>['1020'],
            ),
          ),
          throwsUnsupportedError,
        );
        expect(adapter.requests, isEmpty);
      });

      test('SSRに検索結果件数が無ければ空成功にしない', () async {
        final adapter = _FixtureAdapter(<String, _FixtureResponse>{
          'GET /novels': const _FixtureResponse('''
            <script id="__NUXT_DATA__" type="application/json">
              {"nodes":[]}
            </script>
          '''),
        });

        await expectLater(
          _createSite(adapter).searchNovels(
            const NovelSearchQuery(source: NovelSource.estar),
          ),
          throwsFormatException,
        );
      });
    });
  });
}
