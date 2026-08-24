import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/database/database.dart';
import 'package:novelty/models/episode.dart';
import 'package:novelty/models/novel_info.dart';
import 'package:novelty/repositories/kakuyomu_session_repository.dart';
import 'package:novelty/services/kakuyomu_reading_progress_service.dart';
import 'package:novelty/sites/account_sync_adapter.dart';
import 'package:novelty/sites/kakuyomu/kakuyomu_account_sync_adapter.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:novelty/utils/request_rate_limiter.dart';

class _FakeSessionRepository extends KakuyomuSessionRepository {
  _FakeSessionRepository(this.cookieHeader);

  final String? cookieHeader;

  @override
  Future<String?> buildCookieHeader() async => cookieHeader;
}

RequestRateLimiter _noWaitLimiter() =>
    RequestRateLimiter(interval: Duration.zero);

void main() {
  String fixture(String name) =>
      File('test/fixtures/kakuyomu/$name').readAsStringSync();

  group('KakuyomuAccountSyncAdapter', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.memory();
    });

    tearDown(() async {
      await db.close();
    });

    test('Cookieが無い場合はHTTP取得せずセッション切れを返す', () async {
      var fetched = false;
      final adapter = KakuyomuAccountSyncAdapter(
        sessionRepository: _FakeSessionRepository(null),
        db: db,
        pageFetcher: (url, cookie) async {
          fetched = true;
          throw StateError('呼ばれない');
        },
      );

      await expectLater(
        adapter.pullLibrary(),
        throwsA(isA<KakuyomuSessionExpiredException>()),
      );
      expect(fetched, isFalse);
    });

    test('pullLibraryのページ取得は共有レートリミッターの許可後に始まる', () {
      fakeAsync((async) {
        final limiter = RequestRateLimiter(
          interval: const Duration(milliseconds: 100),
          now: () => async.elapsed,
        );
        var fetched = false;
        var completed = false;
        unawaited(limiter.wait());
        async.flushMicrotasks();

        final adapter = KakuyomuAccountSyncAdapter(
          sessionRepository: _FakeSessionRepository('session=test'),
          db: db,
          rateLimiter: limiter,
          pageFetcher: (url, cookie) async {
            fetched = true;
            return KakuyomuFollowedWorksHttpResponse(
              statusCode: 200,
              realUri: url,
              body: '',
            );
          },
        );
        unawaited(adapter.pullLibrary().then((_) => completed = true));

        async.flushMicrotasks();
        expect(fetched, isFalse);
        expect(completed, isFalse);

        async.elapse(const Duration(milliseconds: 99));
        expect(fetched, isFalse);

        async.elapse(const Duration(milliseconds: 1));
        expect(fetched, isTrue);
        expect(completed, isTrue);
      });
    });

    test('ログイン画面へ戻された場合はセッション切れを返す', () async {
      final adapter = KakuyomuAccountSyncAdapter(
        sessionRepository: _FakeSessionRepository('session=test'),
        db: db,
        rateLimiter: _noWaitLimiter(),
        pageFetcher: (url, cookie) async {
          return KakuyomuFollowedWorksHttpResponse(
            statusCode: 200,
            realUri: Uri.parse('https://kakuyomu.jp/auth/login'),
            body: '<html></html>',
          );
        },
      );

      await expectLater(
        adapter.pullLibrary(),
        throwsA(isA<KakuyomuSessionExpiredException>()),
      );
      expect(await db.getLibraryNovels(), isEmpty);
    });

    test('guestページを返された場合は空一覧ではなくセッション切れを返す', () async {
      final adapter = KakuyomuAccountSyncAdapter(
        sessionRepository: _FakeSessionRepository('session=test'),
        db: db,
        rateLimiter: _noWaitLimiter(),
        pageFetcher: (url, cookie) async {
          return KakuyomuFollowedWorksHttpResponse(
            statusCode: 200,
            realUri: url,
            body: '''
              <html>
                <body id="page-my-antenna-worksGuest">
                  <h3>ユーザー登録して更新情報をチェック</h3>
                </body>
              </html>
            ''',
          );
        },
      );

      await expectLater(
        adapter.pullLibrary(),
        throwsA(isA<KakuyomuSessionExpiredException>()),
      );
      expect(await db.getLibraryNovels(), isEmpty);
    });

    test('複数作品をライブラリへ追加し作者名を保存して重複同期では0件', () async {
      final html = fixture('followed_works_page.html').replaceFirst(
        '<a href="/my/antenna/works/all?page=2&amp;order=last_read_at">\n      <i class="icon-next-large"></i>\n    </a>',
        '',
      );
      final adapter = KakuyomuAccountSyncAdapter(
        sessionRepository: _FakeSessionRepository('session=test'),
        db: db,
        rateLimiter: _noWaitLimiter(),
        pageFetcher: (url, cookie) async {
          return KakuyomuFollowedWorksHttpResponse(
            statusCode: 200,
            realUri: url,
            body: html,
          );
        },
      );

      expect(await adapter.pullLibrary(), 2);
      expect(await adapter.pullLibrary(), 0);
      expect(await db.getLibraryNovels(), hasLength(2));
      final first = await db.getNovel(
        NovelSource.kakuyomu,
        '1177354054880000001',
      );
      expect(first?.writer, 'テスト作者 1');
    });

    test('既存の詳細メタデータを一覧由来の値で上書きしない', () async {
      const workId = '1177354054880000001';
      await db.insertNovel(
        const NovelInfo(
          source: NovelSource.kakuyomu,
          workId: workId,
          title: '既存の詳細タイトル',
          writer: '既存作者',
          story: '既存あらすじ',
          generalAllNo: 100,
        ).toDbCompanion(),
      );

      final html = fixture('followed_works_page.html').replaceFirst(
        '<a href="/my/antenna/works/all?page=2&amp;order=last_read_at">\n      <i class="icon-next-large"></i>\n    </a>',
        '',
      );
      final adapter = KakuyomuAccountSyncAdapter(
        sessionRepository: _FakeSessionRepository('session=test'),
        db: db,
        rateLimiter: _noWaitLimiter(),
        pageFetcher: (url, cookie) async => KakuyomuFollowedWorksHttpResponse(
          statusCode: 200,
          realUri: url,
          body: html,
        ),
      );

      await adapter.pullLibrary();
      final stored = await db.getNovel(NovelSource.kakuyomu, workId);
      expect(stored?.title, '既存の詳細タイトル');
      expect(stored?.writer, '既存作者');
      expect(stored?.story, '既存あらすじ');
      expect(stored?.generalAllNo, 100);
    });

    test('サイト側の最終読書エピソードをローカル履歴へmergeする', () async {
      final html = fixture('followed_works_page.html').replaceFirst(
        '<a href="/my/antenna/works/all?page=2&amp;order=last_read_at">\n'
            '      <i class="icon-next-large"></i>\n'
            '    </a>',
        '',
      );
      final adapter = KakuyomuAccountSyncAdapter(
        sessionRepository: _FakeSessionRepository('session=test'),
        db: db,
        rateLimiter: _noWaitLimiter(),
        pageFetcher: (url, cookie) async => KakuyomuFollowedWorksHttpResponse(
          statusCode: 200,
          realUri: url,
          body: html,
        ),
        fetchRemoteReadingState: (workId) async => KakuyomuRemoteReadingState(
          isAvailable: true,
          episodeId: workId == '1177354054880000001'
              ? '1177354054881000001'
              : null,
        ),
        episodeListResolver: (workId) async => [
          Episode(
            source: NovelSource.kakuyomu,
            index: 1,
            url:
                'https://kakuyomu.jp/works/$workId/episodes/'
                '1177354054881000001',
          ),
        ],
      );

      await adapter.pullLibrary();

      final history = await db.getHistory();
      final first = history.singleWhere(
        (entry) => entry.workId == '1177354054880000001',
      );
      expect(first.lastEpisode, 1);
    });

    test('addToRemoteLibraryはネイティブfollow操作へ委譲する', () async {
      String? capturedWorkId;
      final adapter = KakuyomuAccountSyncAdapter(
        sessionRepository: _FakeSessionRepository('session=test'),
        db: db,
        followWork: (workId) async {
          capturedWorkId = workId;
          return AccountSyncOutcome.success;
        },
      );

      final result = await adapter.addToRemoteLibrary('123456789');

      expect(result, AccountSyncOutcome.success);
      expect(capturedWorkId, '123456789');
    });

    test('removeFromRemoteLibraryはネイティブunfollow操作へ委譲する', () async {
      String? capturedWorkId;
      final adapter = KakuyomuAccountSyncAdapter(
        sessionRepository: _FakeSessionRepository('session=test'),
        db: db,
        unfollowWork: (workId) async {
          capturedWorkId = workId;
          return AccountSyncOutcome.notLoggedIn;
        },
      );

      final result = await adapter.removeFromRemoteLibrary('123456789');

      expect(result, AccountSyncOutcome.notLoggedIn);
      expect(capturedWorkId, '123456789');
    });
  });
}
