import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hameln_parser/hameln_parser.dart';
import 'package:novelty/models/novel_info.dart';
import 'package:novelty/sites/hameln/hameln_site.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:novelty/utils/request_rate_limiter.dart';

String _fixture(String name) =>
    File('test/fixtures/hameln/$name').readAsStringSync();

class _FixtureAdapter implements HttpClientAdapter {
  _FixtureAdapter(
    this.fixtures, {
    this.statusCodes = const <String, int>{},
  });

  final Map<String, String> fixtures;
  final Map<String, int> statusCodes;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final uri = Uri.parse(options.path);
    final body = fixtures[uri.toString()] ?? fixtures[uri.path];
    if (body == null) {
      return ResponseBody.fromString('not found', 404);
    }
    return ResponseBody.fromString(
      body,
      statusCodes[uri.toString()] ?? statusCodes[uri.path] ?? 200,
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

HamelnSite _createSite(
  _FixtureAdapter adapter, {
  RequestRateLimiter? rateLimiter,
}) {
  final dio = Dio()..httpClientAdapter = adapter;
  return HamelnSite(
    dio: dio,
    rateLimiter: rateLimiter ?? RequestRateLimiter(interval: Duration.zero),
  );
}

void main() {
  group('HamelnSite', () {
    test('本文パーサ・評価表示・確定済みマスタデータを提供する', () {
      final site = HamelnSite(
        dio: Dio(),
        rateLimiter: RequestRateLimiter(interval: Duration.zero),
      );

      final content = site.parseEpisodeBody(_fixture('episode_ruby.html'));

      expect(site.source, NovelSource.hameln);
      expect(content.whereType<RubyText>(), hasLength(5));
      expect(
        site.metaText(
          const NovelInfo(source: NovelSource.hameln, allPoint: 83),
        ),
        '評価 83',
      );
      expect(
        site.metaText(const NovelInfo(source: NovelSource.hameln)),
        isNull,
      );
      expect(site.genres, isEmpty);
      expect(site.rankingTypes, hasLength(18));
      expect(
        site.rankingTypes.map((type) => type.id),
        containsAll(<String>[
          'rank_day',
          'rank_week',
          'rank_total',
          'rank_new',
        ]),
      );
    });

    group('fetchNovelInfo', () {
      test('連載作品DOMから確定できる作品情報を返す', () async {
        final adapter = _FixtureAdapter(<String, String>{
          '/novel/328453/': _fixture('serial.html'),
        });

        final info = await _createSite(adapter).fetchNovelInfo('328453');

        expect(info.source, NovelSource.hameln);
        expect(info.workId, '328453');
        expect(info.ncode, isNull);
        expect(info.title, '道化の愉快な仲間たち');
        expect(info.writer, 'UBW・HF');
        expect(info.story, contains('失われるはずだった記憶'));
        expect(info.genreId, isNull);
        expect(info.keyword, 'ベル・クラネル');
        expect(info.novelType, 1);
        expect(info.end, isNull);
        expect(info.generalAllNo, 2);
      });

      test('本文を含む作品ページを短編・完結として返す', () async {
        final adapter = _FixtureAdapter(<String, String>{
          '/novel/424174/': _fixture('short.html'),
        });

        final info = await _createSite(adapter).fetchNovelInfo('424174');

        expect(info.source, NovelSource.hameln);
        expect(info.workId, '424174');
        expect(info.ncode, isNull);
        expect(info.title, 'とっとと告れ！そして付き合えと王国臣民は叫んだ。');
        expect(info.writer, '好きって言えない二人良いよね');
        expect(info.novelType, 2);
        expect(info.end, 0);
        expect(info.generalAllNo, 1);
      });

      test('HTTP 200の削除・誤URLページを明確な例外にする', () async {
        final adapter = _FixtureAdapter(<String, String>{
          '/novel/999999999/': '''
            <html><title>エラー</title><body>
              投稿者が削除、もしくは間違ったアドレスを指定しています
            </body></html>
          ''',
        });

        await expectLater(
          _createSite(adapter).fetchNovelInfo('999999999'),
          throwsA(isA<HamelnWorkNotFoundException>()),
        );
      });
    });

    group('fetchToc', () {
      test('連載の全話を目次順の1始まり連番で返す', () async {
        final adapter = _FixtureAdapter(<String, String>{
          '/novel/328453/': _fixture('toc.html'),
        });

        final episodes = await _createSite(adapter).fetchToc('328453');

        expect(episodes, hasLength(2));
        expect(episodes.map((episode) => episode.index), <int?>[1, 2]);
        expect(episodes.first.source, NovelSource.hameln);
        expect(episodes.first.subtitle, 'エイプリルフール');
        expect(
          episodes.first.url,
          'https://syosetu.org/novel/328453/1.html',
        );
        expect(episodes.first.update, '2025/04/01 23:55');
        expect(episodes.first.revised, '2025/04/02 07:09');
        expect(episodes.last.index, 2);
        expect(
          episodes.last.url,
          'https://syosetu.org/novel/328453/3.html',
        );
      });

      test('短編は作品URL自体を第1話として返す', () async {
        final adapter = _FixtureAdapter(<String, String>{
          '/novel/424174/': _fixture('short.html'),
        });

        final episodes = await _createSite(adapter).fetchToc('424174');

        expect(episodes, hasLength(1));
        expect(episodes.single.source, NovelSource.hameln);
        expect(episodes.single.index, 1);
        expect(episodes.single.subtitle, '第1話');
        expect(
          episodes.single.url,
          'https://syosetu.org/novel/424174/',
        );
      });

      test('作品情報と目次で同じ作品HTMLをキャッシュ共有する', () async {
        final adapter = _FixtureAdapter(<String, String>{
          '/novel/328453/': _fixture('serial.html'),
        });
        final site = _createSite(adapter);

        await site.fetchNovelInfo('328453');
        await site.fetchToc('328453');

        expect(adapter.requests, hasLength(1));
      });
    });

    group('fetchEpisode', () {
      test('解決済みURLから本文を取得し共通レートリミッタを経由する', () async {
        const episodeUrl = 'https://syosetu.org/novel/328453/1.html';
        final adapter = _FixtureAdapter(<String, String>{
          '/novel/328453/1.html': _fixture('episode.html'),
        });
        final limiter = _CountingRateLimiter();

        final episode = await _createSite(
          adapter,
          rateLimiter: limiter,
        ).fetchEpisode('328453', 1, url: episodeUrl);

        expect(episode.source, NovelSource.hameln);
        expect(episode.index, 1);
        expect(episode.subtitle, '第1話');
        expect(episode.url, episodeUrl);
        expect(episode.body, contains('<div id="honbun">'));
        expect(adapter.requests, hasLength(1));
        expect(limiter.waitCount, 1);
      });

      test('短編の作品URLから第1話本文と話タイトルを返す', () async {
        const workUrl = 'https://syosetu.org/novel/424174/';
        final adapter = _FixtureAdapter(<String, String>{
          '/novel/424174/': _fixture('short.html'),
        });

        final episode = await _createSite(
          adapter,
        ).fetchEpisode('424174', 1, url: workUrl);

        expect(episode.index, 1);
        expect(episode.subtitle, '第1話');
        expect(episode.url, workUrl);
        expect(episode.body, contains('<div id="honbun">'));
      });

      test('R18ワンクッションを判別して回避せず例外にする', () async {
        const episodeUrl = 'https://h.syosetu.org/novel/123456/1.html';
        final adapter = _FixtureAdapter(<String, String>{
          episodeUrl: '''
            <html><head><title>R18閲覧確認ページ</title></head><body>
              <p>あなたは18歳以上ですか？</p>
              <a href="?cookie_set=r18">はい</a>
            </body></html>
          ''',
        });

        await expectLater(
          _createSite(adapter).fetchEpisode('123456', 1, url: episodeUrl),
          throwsA(isA<HamelnAgeConfirmationException>()),
        );
      });

      test('公式外URLとrobots.txt禁止URLはHTTPリクエスト前に拒否する', () async {
        final adapter = _FixtureAdapter(<String, String>{});
        final site = _createSite(adapter);

        for (final url in <String>[
          'https://example.com/novel/328453/1.html',
          'https://syosetu.org/novel/328453/1.html?mode=ss_detail3',
          'https://syosetu.org/conv/pdf/328453/',
        ]) {
          await expectLater(
            site.fetchEpisode('328453', 1, url: url),
            throwsStateError,
          );
        }
        expect(adapter.requests, isEmpty);
      });
    });

    group('fetchRanking', () {
      test('実HTMLの日間ランキング100件を作品情報として返す', () async {
        final adapter = _FixtureAdapter(<String, String>{
          'https://syosetu.org/?mode=rank_day': _fixture('ranking.html'),
        });

        final page = await _createSite(adapter).fetchRanking('rank_day');

        expect(page.novels, hasLength(100));
        expect(page.hasNextPage, isFalse);
        final first = page.novels.first;
        expect(first.source, NovelSource.hameln);
        expect(first.workId, '423921');
        expect(first.ncode, isNull);
        expect(first.title, '“パエトーン”に過剰反応する系の偽旅人');
        expect(first.writer, '融合好き');
        expect(first.story, contains('元原神プレイヤー'));
        expect(first.novelType, 1);
        expect(first.end, 1);
        expect(first.generalAllNo, 3);
        expect(first.totalCharacterCount, 19220);
        expect(first.allPoint, 7557);
        expect(first.favNovelCnt, 1720);
        expect(first.impressionCnt, 12);
        expect(first.allHyokaCnt, 57);
        expect(first.generalLastup, '2026-08-24 06:48:00');
        expect(first.keyword, contains('ゼンレスゾーンゼロ'));
        expect(first.keyword, contains('R-15'));
        final completed = page.novels.singleWhere(
          (novel) => novel.workId == '268507',
        );
        expect(completed.novelType, 1);
        expect(completed.end, 0);
        expect(completed.generalAllNo, 31);
        final short = page.novels.singleWhere(
          (novel) => novel.workId == '423012',
        );
        expect(short.novelType, 2);
        expect(short.end, 0);
        expect(short.generalAllNo, 1);
        expect(
          adapter.requests.single.uri.toString(),
          'https://syosetu.org/?mode=rank_day',
        );
      });

      test('CloudflareのJavaScriptチャレンジを明確な例外にする', () async {
        final adapter = _FixtureAdapter(<String, String>{
          'https://syosetu.org/?mode=rank_day': _fixture(
            'ranking_cloudflare.html',
          ),
        });

        await expectLater(
          _createSite(adapter).fetchRanking('rank_day'),
          throwsA(isA<HamelnCloudflareChallengeException>()),
        );
      });

      test('HTTP 403をアクセス制限の例外にする', () async {
        const url = 'https://syosetu.org/?mode=rank_day';
        final adapter = _FixtureAdapter(
          <String, String>{url: 'Forbidden'},
          statusCodes: const <String, int>{url: 403},
        );

        await expectLater(
          _createSite(adapter).fetchRanking('rank_day'),
          throwsA(isA<HamelnCloudflareChallengeException>()),
        );
      });

      test('明示更新は取得済みHTMLを使わず再取得する', () async {
        final adapter = _FixtureAdapter(<String, String>{
          'https://syosetu.org/?mode=rank_day': _fixture('ranking.html'),
        });
        final site = _createSite(adapter);

        await site.fetchRanking('rank_day');
        await site.fetchRanking('rank_day');
        expect(adapter.requests, hasLength(1));

        await site.refreshRanking('rank_day');

        expect(adapter.requests, hasLength(2));
      });

      test('未確認の2ページ目以降はHTTP取得せず空で終端する', () async {
        final adapter = _FixtureAdapter(<String, String>{});

        final page = await _createSite(
          adapter,
        ).fetchRanking('rank_day', page: 2);

        expect(page.novels, isEmpty);
        expect(page.hasNextPage, isFalse);
        expect(adapter.requests, isEmpty);
      });

      test('ランキング取得は共有レートリミッタを経由する', () async {
        final adapter = _FixtureAdapter(<String, String>{
          'https://syosetu.org/?mode=rank_day': _fixture('ranking.html'),
        });
        final limiter = _CountingRateLimiter();

        await _createSite(
          adapter,
          rateLimiter: limiter,
        ).fetchRanking('rank_day');

        expect(adapter.requests, hasLength(1));
        expect(limiter.waitCount, 1);
      });
    });
  });
}
