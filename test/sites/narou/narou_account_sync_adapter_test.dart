import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:novelty/services/narou_sync_service.dart';
import 'package:novelty/sites/account_sync_adapter.dart';
import 'package:novelty/sites/narou/narou_account_sync_adapter.dart';
import 'package:novelty/sites/novel_source.dart';

import '../../repositories/library_status_toggle_test.mocks.dart';

void main() {
  group('NarouAccountSyncAdapter', () {
    late MockNarouSyncService syncService;
    late MockAppDatabase db;
    late NarouAccountSyncAdapter adapter;

    const workId = 'n1234ab';

    setUp(() {
      syncService = MockNarouSyncService();
      db = MockAppDatabase();
      adapter = NarouAccountSyncAdapter(syncService: syncService, db: db);
    });

    test('sourceはnarouを返す', () {
      expect(adapter.source, NovelSource.narou);
    });

    test('pullLibraryは同期した作品数を返す', () async {
      when(syncService.syncBookmarksFromNarou()).thenAnswer(
        (_) async => const ['n0001aa', 'n0002bb'],
      );

      expect(await adapter.pullLibrary(), 2);
    });

    test('ブックマーク同期成功を共通successへ変換し同期情報を保存する', () async {
      when(syncService.addBookmarkToNarou(workId)).thenAnswer(
        (_) async => const NarouBookmarkSyncResult(
          outcome: NarouBookmarkSyncOutcome.success,
          useridFavncode: '123_456',
          token: 'token-value',
        ),
      );
      when(
        db.markNarouBookmarkSynced(
          NovelSource.narou,
          workId,
          useridFavncode: anyNamed('useridFavncode'),
          favToken: anyNamed('favToken'),
        ),
      ).thenAnswer((_) async {});

      final result = await adapter.addToRemoteLibrary(workId);

      expect(result, AccountSyncOutcome.success);
      verify(
        db.markNarouBookmarkSynced(
          NovelSource.narou,
          workId,
          useridFavncode: '123_456',
          favToken: 'token-value',
        ),
      ).called(1);
    });

    test('未ログインを共通notLoggedInへ変換し同期情報を保存しない', () async {
      when(syncService.addBookmarkToNarou(workId)).thenAnswer(
        (_) async => const NarouBookmarkSyncResult(
          outcome: NarouBookmarkSyncOutcome.notLoggedIn,
        ),
      );

      final result = await adapter.addToRemoteLibrary(workId);

      expect(result, AccountSyncOutcome.notLoggedIn);
      verifyNever(
        db.markNarouBookmarkSynced(
          NovelSource.narou,
          workId,
          useridFavncode: anyNamed('useridFavncode'),
          favToken: anyNamed('favToken'),
        ),
      );
    });

    test('同期失敗を共通failedへ変換し同期情報を保存しない', () async {
      when(syncService.addBookmarkToNarou(workId)).thenAnswer(
        (_) async => const NarouBookmarkSyncResult(
          outcome: NarouBookmarkSyncOutcome.failed,
        ),
      );

      final result = await adapter.addToRemoteLibrary(workId);

      expect(result, AccountSyncOutcome.failed);
      verifyNever(
        db.markNarouBookmarkSynced(
          NovelSource.narou,
          workId,
          useridFavncode: anyNamed('useridFavncode'),
          favToken: anyNamed('favToken'),
        ),
      );
    });

    test('解除結果を共通結果へ変換する', () async {
      when(syncService.removeBookmarkFromNarou(workId)).thenAnswer(
        (_) async => NarouBookmarkSyncOutcome.success,
      );
      expect(
        await adapter.removeFromRemoteLibrary(workId),
        AccountSyncOutcome.success,
      );

      when(syncService.removeBookmarkFromNarou(workId)).thenAnswer(
        (_) async => NarouBookmarkSyncOutcome.notLoggedIn,
      );
      expect(
        await adapter.removeFromRemoteLibrary(workId),
        AccountSyncOutcome.notLoggedIn,
      );

      when(syncService.removeBookmarkFromNarou(workId)).thenAnswer(
        (_) async => NarouBookmarkSyncOutcome.failed,
      );
      expect(
        await adapter.removeFromRemoteLibrary(workId),
        AccountSyncOutcome.failed,
      );
    });

    test('pushReadingProgressは既存しおり同期へ委譲する', () async {
      when(
        syncService.setShioriIfLoggedIn(ncode: workId, episode: 12),
      ).thenAnswer((_) async => true);

      final result = await adapter.pushReadingProgress(
        workId: workId,
        episode: 12,
      );

      expect(result, isTrue);
      verify(
        syncService.setShioriIfLoggedIn(ncode: workId, episode: 12),
      ).called(1);
    });
  });
}
