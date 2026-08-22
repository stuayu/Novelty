import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/database/database.dart';
import 'package:novelty/models/novel_info.dart';
import 'package:novelty/repositories/kakuyomu_session_repository.dart';
import 'package:novelty/sites/account_sync_adapter.dart';
import 'package:novelty/sites/kakuyomu/kakuyomu_account_sync_adapter.dart';
import 'package:novelty/sites/novel_source.dart';

class _FakeSessionRepository extends KakuyomuSessionRepository {
  _FakeSessionRepository(this.cookieHeader);

  final String? cookieHeader;

  @override
  Future<String?> buildCookieHeader() async => cookieHeader;
}

void main() {
  String fixture(String name) =>
      File('test/fixtures/kakuyomu/$name').readAsStringSync();

  group('KakuyomuAccountSyncAdapter.pullLibrary', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.memory();
    });

    tearDown(() async {
      await db.close();
    });

    test('Cookieが無い場合はHTTP取得せず0件', () async {
      var fetched = false;
      final adapter = KakuyomuAccountSyncAdapter(
        sessionRepository: _FakeSessionRepository(null),
        db: db,
        pageFetcher: (url, cookie) async {
          fetched = true;
          throw StateError('呼ばれない');
        },
      );

      expect(await adapter.pullLibrary(), 0);
      expect(fetched, isFalse);
    });

    test('ログイン画面へ戻された場合は0件', () async {
      final adapter = KakuyomuAccountSyncAdapter(
        sessionRepository: _FakeSessionRepository('session=test'),
        db: db,
        pageFetcher: (url, cookie) async {
          return KakuyomuFollowedWorksHttpResponse(
            statusCode: 200,
            realUri: Uri.parse('https://kakuyomu.jp/auth/login'),
            body: '<html></html>',
          );
        },
      );

      expect(await adapter.pullLibrary(), 0);
      expect(await db.getLibraryNovels(), isEmpty);
    });

    test('複数作品をライブラリへ追加し重複同期では0件', () async {
      final html = fixture('followed_works_page.html').replaceFirst(
        '<a href="/my/antenna/works/all?page=2&amp;order=last_read_at">\n      <i class="icon-next-large"></i>\n    </a>',
        '',
      );
      final adapter = KakuyomuAccountSyncAdapter(
        sessionRepository: _FakeSessionRepository('session=test'),
        db: db,
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
        pageFetcher: (url, cookie) async =>
            KakuyomuFollowedWorksHttpResponse(
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
  });

  group('KakuyomuAccountSyncAdapter remote follow', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.memory();
    });

    tearDown(() async {
      await db.close();
    });

    test('addToRemoteLibraryはfollow=trueで委譲する', () async {
      String? receivedWorkId;
      bool? receivedShouldFollow;
      final adapter = KakuyomuAccountSyncAdapter(
        sessionRepository: _FakeSessionRepository('session=test'),
        db: db,
        followOperator: (workId, {required shouldFollow}) async {
          receivedWorkId = workId;
          receivedShouldFollow = shouldFollow;
          return AccountSyncOutcome.success;
        },
      );

      final result = await adapter.addToRemoteLibrary('1177354054880000001');

      expect(result, AccountSyncOutcome.success);
      expect(receivedWorkId, '1177354054880000001');
      expect(receivedShouldFollow, isTrue);
    });

    test('removeFromRemoteLibraryはfollow=falseで委譲する', () async {
      bool? receivedShouldFollow;
      final adapter = KakuyomuAccountSyncAdapter(
        sessionRepository: _FakeSessionRepository('session=test'),
        db: db,
        followOperator: (workId, {required shouldFollow}) async {
          receivedShouldFollow = shouldFollow;
          return AccountSyncOutcome.notLoggedIn;
        },
      );

      final result = await adapter.removeFromRemoteLibrary(
        '1177354054880000001',
      );

      expect(result, AccountSyncOutcome.notLoggedIn);
      expect(receivedShouldFollow, isFalse);
    });

    test('フォロー操作失敗をfailedのまま返す', () async {
      final adapter = KakuyomuAccountSyncAdapter(
        sessionRepository: _FakeSessionRepository('session=test'),
        db: db,
        followOperator: (workId, {required shouldFollow}) async =>
            AccountSyncOutcome.failed,
      );

      expect(
        await adapter.addToRemoteLibrary('1177354054880000001'),
        AccountSyncOutcome.failed,
      );
      expect(
        await adapter.removeFromRemoteLibrary('1177354054880000001'),
        AccountSyncOutcome.failed,
      );
    });
  });
}
