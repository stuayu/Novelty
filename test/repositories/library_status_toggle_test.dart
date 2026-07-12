import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:novelty/database/database.dart';
import 'package:novelty/models/library_toggle_result.dart';
import 'package:novelty/models/novel_info.dart';
import 'package:novelty/repositories/novel_repository.dart';
import 'package:novelty/services/narou_sync_service.dart';

import 'library_status_toggle_test.mocks.dart';

@GenerateMocks([AppDatabase, NarouSyncService])
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LibraryStatus.toggle', () {
    late MockAppDatabase mockDatabase;
    late MockNarouSyncService mockNarouSyncService;
    late ProviderContainer container;

    const testNcode = 'n1234ab';
    const testNovel = NovelInfo(ncode: testNcode, title: 'テスト小説');

    setUp(() {
      mockDatabase = MockAppDatabase();
      mockNarouSyncService = MockNarouSyncService();
      when(mockDatabase.watchIsInLibrary(any)).thenAnswer(
        (_) => Stream.value(false),
      );
      container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(mockDatabase),
          narouSyncServiceProvider.overrideWithValue(mockNarouSyncService),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('なろう同期成功時はnarouSyncFailed:falseで同期済みを記録する', () async {
      when(mockDatabase.insertNovel(any)).thenAnswer((_) async => 1);
      when(mockDatabase.addToLibrary(testNcode)).thenAnswer((_) async => 1);
      when(mockNarouSyncService.addBookmarkToNarou(testNcode)).thenAnswer(
        (_) async => const NarouBookmarkSyncResult(
          outcome: NarouBookmarkSyncOutcome.success,
          useridFavncode: '1119968_3231307',
          token: 'abcxyz',
        ),
      );
      when(
        mockDatabase.markNarouBookmarkSynced(
          testNcode,
          useridFavncode: anyNamed('useridFavncode'),
          favToken: anyNamed('favToken'),
        ),
      ).thenAnswer((_) async {});

      final result = await container
          .read(libraryStatusProvider(testNcode).notifier)
          .toggle(testNovel);

      expect(result, const LibraryToggleResult.added());
      verify(
        mockDatabase.markNarouBookmarkSynced(
          testNcode,
          useridFavncode: '1119968_3231307',
          favToken: 'abcxyz',
        ),
      ).called(1);
    });

    test('なろう同期失敗時はnarouSyncFailed:trueを返し同期済みにしない', () async {
      when(mockDatabase.insertNovel(any)).thenAnswer((_) async => 1);
      when(mockDatabase.addToLibrary(testNcode)).thenAnswer((_) async => 1);
      when(mockNarouSyncService.addBookmarkToNarou(testNcode)).thenAnswer(
        (_) async => const NarouBookmarkSyncResult(
          outcome: NarouBookmarkSyncOutcome.failed,
        ),
      );

      final result = await container
          .read(libraryStatusProvider(testNcode).notifier)
          .toggle(testNovel);

      expect(
        result,
        const LibraryToggleResult.added(narouSyncFailed: true),
      );
      verifyNever(
        mockDatabase.markNarouBookmarkSynced(
          testNcode,
          useridFavncode: anyNamed('useridFavncode'),
          favToken: anyNamed('favToken'),
        ),
      );
    });

    test('なろう同期で予期しない例外が発生してもローカル追加はerrorにならない', () async {
      when(mockDatabase.insertNovel(any)).thenAnswer((_) async => 1);
      when(mockDatabase.addToLibrary(testNcode)).thenAnswer((_) async => 1);
      when(
        mockNarouSyncService.addBookmarkToNarou(testNcode),
      ).thenThrow(Exception('予期しないエラー'));

      final result = await container
          .read(libraryStatusProvider(testNcode).notifier)
          .toggle(testNovel);

      expect(
        result,
        const LibraryToggleResult.added(narouSyncFailed: true),
      );
      verify(mockDatabase.addToLibrary(testNcode)).called(1);
      verifyNever(
        mockDatabase.markNarouBookmarkSynced(
          testNcode,
          useridFavncode: anyNamed('useridFavncode'),
          favToken: anyNamed('favToken'),
        ),
      );
    });

    test('未ログイン時はnarouSyncFailed:falseを返す（警告不要）', () async {
      when(mockDatabase.insertNovel(any)).thenAnswer((_) async => 1);
      when(mockDatabase.addToLibrary(testNcode)).thenAnswer((_) async => 1);
      when(mockNarouSyncService.addBookmarkToNarou(testNcode)).thenAnswer(
        (_) async => const NarouBookmarkSyncResult(
          outcome: NarouBookmarkSyncOutcome.notLoggedIn,
        ),
      );

      final result = await container
          .read(libraryStatusProvider(testNcode).notifier)
          .toggle(testNovel);

      expect(result, const LibraryToggleResult.added());
      verifyNever(
        mockDatabase.markNarouBookmarkSynced(
          testNcode,
          useridFavncode: anyNamed('useridFavncode'),
          favToken: anyNamed('favToken'),
        ),
      );
    });

    /// [libraryStatusProvider]が「登録済み(true)」の初期状態を読み込むまで待つ。
    ///
    /// 自動破棄によるriverpodのタイミング問題を避けるため`.future`は使わない。
    Future<LibraryStatus> waitForRegisteredState() async {
      final notifier = container.read(
        libraryStatusProvider(testNcode).notifier,
      );
      final completer = Completer<void>();
      final subscription = container.listen(
        libraryStatusProvider(testNcode),
        (previous, next) {
          if (next.value == true && !completer.isCompleted) {
            completer.complete();
          }
        },
        fireImmediately: true,
      );
      await completer.future;
      subscription.close();
      return notifier;
    }

    test('保存トークンが無くてもncodeを使ってなろう解除を呼ぶ', () async {
      when(mockDatabase.watchIsInLibrary(testNcode)).thenAnswer(
        (_) => Stream.value(true),
      );
      when(mockDatabase.removeFromLibrary(testNcode)).thenAnswer(
        (_) async => 1,
      );
      when(mockNarouSyncService.removeBookmarkFromNarou(testNcode))
          .thenAnswer((_) async => NarouBookmarkSyncOutcome.success);

      final notifier = await waitForRegisteredState();
      final result = await notifier.toggle(testNovel);

      expect(result, const LibraryToggleResult.removed());
      verify(mockNarouSyncService.removeBookmarkFromNarou(testNcode)).called(1);
    });

    test('なろう解除成功時はnarouSyncFailed:falseでremovedを返す', () async {
      when(mockDatabase.watchIsInLibrary(testNcode)).thenAnswer(
        (_) => Stream.value(true),
      );
      when(mockDatabase.removeFromLibrary(testNcode)).thenAnswer(
        (_) async => 1,
      );
      when(
        mockNarouSyncService.removeBookmarkFromNarou(testNcode),
      ).thenAnswer((_) async => NarouBookmarkSyncOutcome.success);

      final notifier = await waitForRegisteredState();
      final result = await notifier.toggle(testNovel);

      expect(result, const LibraryToggleResult.removed());
      verify(mockNarouSyncService.removeBookmarkFromNarou(testNcode)).called(1);
    });

    test('なろう解除失敗時はnarouSyncFailed:trueでremovedを返す', () async {
      when(mockDatabase.watchIsInLibrary(testNcode)).thenAnswer(
        (_) => Stream.value(true),
      );
      when(mockDatabase.removeFromLibrary(testNcode)).thenAnswer(
        (_) async => 1,
      );
      when(
        mockNarouSyncService.removeBookmarkFromNarou(testNcode),
      ).thenAnswer((_) async => NarouBookmarkSyncOutcome.failed);

      final notifier = await waitForRegisteredState();
      final result = await notifier.toggle(testNovel);

      expect(
        result,
        const LibraryToggleResult.removed(narouSyncFailed: true),
      );
      verifyNever(mockDatabase.removeFromLibrary(testNcode));
    });
  });
}
