import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:novelty/database/database.dart';
import 'package:novelty/repositories/auth_repository.dart';
import 'package:novelty/services/api_service.dart';
import 'package:novelty/services/narou_sync_service.dart';

import 'narou_sync_service_test.mocks.dart';

@GenerateMocks([AuthRepository, AppDatabase, ApiService])
void main() {
  group('NarouSyncService', () {
    late MockAuthRepository mockAuthRepository;
    late MockAppDatabase mockDatabase;
    late MockApiService mockApiService;
    late NarouSyncService syncService;

    setUp(() {
      mockAuthRepository = MockAuthRepository();
      mockDatabase = MockAppDatabase();
      mockApiService = MockApiService();
      syncService = NarouSyncService(
        authRepository: mockAuthRepository,
        db: mockDatabase,
        apiService: mockApiService,
      );
    });

    group('syncBookmarksFromNarou', () {
      test('セッションCookieがない場合は空リストを返す', () async {
        when(mockAuthRepository.buildCookieHeader())
            .thenAnswer((_) async => null);

        final result = await syncService.syncBookmarksFromNarou();
        expect(result, isEmpty);
        verifyNever(mockDatabase.addToLibrary(any));
      });
    });

    group('addBookmarkToNarou', () {
      test('セッションCookieがない場合はfalseを返す', () async {
        when(mockAuthRepository.buildCookieHeader())
            .thenAnswer((_) async => null);

        final result = await syncService.addBookmarkToNarou('n0156ia');
        expect(result, isFalse);
      });
    });

    group('setShioriIfLoggedIn', () {
      test('セッションCookieがない場合は何もしない', () async {
        when(mockAuthRepository.buildCookieHeader())
            .thenAnswer((_) async => null);

        await syncService.setShioriIfLoggedIn(
          ncode: 'n0156ia',
          episode: 1,
        );
        verifyNever(mockDatabase.isInLibrary(any));
      });

      test('ライブラリ未登録の場合はしおりを設定しない', () async {
        when(mockAuthRepository.buildCookieHeader())
            .thenAnswer((_) async => 'ks2=x; ses=y; userl=z');
        when(mockDatabase.isInLibrary('n0156ia'))
            .thenAnswer((_) async => false);

        await syncService.setShioriIfLoggedIn(
          ncode: 'n0156ia',
          episode: 1,
        );
        verify(mockDatabase.isInLibrary('n0156ia')).called(1);
      });
    });

    group('NarouBookmarkEntry', () {
      test('正しく生成される', () {
        const entry = NarouBookmarkEntry(ncode: 'n0156ia', shioriEpisode: 5);
        expect(entry.ncode, equals('n0156ia'));
        expect(entry.shioriEpisode, equals(5));
      });

      test('しおり位置なしで生成される', () {
        const entry = NarouBookmarkEntry(ncode: 'n0156ia');
        expect(entry.ncode, equals('n0156ia'));
        expect(entry.shioriEpisode, isNull);
      });
    });
  });
}
