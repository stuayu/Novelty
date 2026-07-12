import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:novelty/database/database.dart' as db;
import 'package:novelty/models/episode.dart';
import 'package:novelty/providers/connectivity_provider.dart';
import 'package:novelty/repositories/novel_repository.dart';
import 'package:novelty/services/api_service.dart';
import 'package:novelty/utils/ncode_utils.dart';
import 'package:novelty/utils/settings_provider.dart';

import '../providers/novel_info_offline_test.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NovelRepository fetchEpisodeList', () {
    late MockAppDatabase mockDatabase;
    late MockApiService mockApiService;
    late ProviderContainer container;

    setUp(() {
      mockDatabase = MockAppDatabase();
      mockApiService = MockApiService();
    });

    ProviderContainer createContainer({bool isOffline = false}) {
      return ProviderContainer(
        overrides: [
          db.appDatabaseProvider.overrideWithValue(mockDatabase),
          apiServiceProvider.overrideWithValue(mockApiService),
          settingsProvider.overrideWith(FakeSettings.new),
          isOfflineProvider.overrideWithValue(isOffline),
        ],
      );
    }

    tearDown(() {
      container.dispose();
    });

    const testNcode = 'N1234AB';
    final normalizedNcode = testNcode.toNormalizedNcode();
    const page = 1;

    test('should return cached episodes when offline', () async {
      container = createContainer(isOffline: true); // Offline

      when(mockDatabase.getEpisodesRange(normalizedNcode, 1, 100)).thenAnswer(
        (_) async => [
          const Episode(
            ncode: 'n1234ab',
            index: 1,
            subtitle: 'Ep 1',
            url: 'http://example.com/1/',
          ),
        ],
      );

      final repository = container.read(novelRepositoryProvider);
      final result = await repository.fetchEpisodeList(testNcode, page);

      expect(result.length, 1);
      expect(result.first.subtitle, 'Ep 1');
      verify(mockDatabase.getEpisodesRange(normalizedNcode, 1, 100)).called(1);
      verifyNever(mockApiService.fetchEpisodeList(any, any));
    });

    test('should fetch from API and save to DB when online', () async {
      container = createContainer(); // Online

      final episodes = [
        const Episode(
          ncode: 'n1234ab',
          index: 1,
          subtitle: 'Ep 1',
          url: 'http://example.com/1/',
        ),
      ];

      when(
        mockApiService.fetchEpisodeList(normalizedNcode, page),
      ).thenAnswer((_) async => episodes);

      when(mockDatabase.upsertEpisodes(any)).thenAnswer((_) async => {});

      final repository = container.read(novelRepositoryProvider);
      final result = await repository.fetchEpisodeList(testNcode, page);

      expect(result.length, 1);
      expect(result.first.subtitle, 'Ep 1');
      verify(mockApiService.fetchEpisodeList(normalizedNcode, page)).called(1);
      verify(mockDatabase.upsertEpisodes(any)).called(1);
    });

    test('should fallback to cache when online fetch fails', () async {
      container = createContainer(); // Online

      when(
        mockApiService.fetchEpisodeList(normalizedNcode, page),
      ).thenThrow(Exception('Network Error'));

      when(mockDatabase.getEpisodesRange(normalizedNcode, 1, 100)).thenAnswer(
        (_) async => [
          const Episode(
            ncode: 'n1234ab',
            index: 1,
            subtitle: 'Ep 1',
            url: 'http://example.com/1/',
          ),
        ],
      );

      final repository = container.read(novelRepositoryProvider);
      final result = await repository.fetchEpisodeList(testNcode, page);

      expect(result.length, 1);
      expect(result.first.subtitle, 'Ep 1');
      verify(mockApiService.fetchEpisodeList(normalizedNcode, page)).called(1);
      verify(mockDatabase.getEpisodesRange(normalizedNcode, 1, 100)).called(1);
    });
  });

  group('NovelRepository refreshStaleLibraryMetadata', () {
    late MockAppDatabase mockDatabase;
    late MockApiService mockApiService;
    late ProviderContainer container;

    setUp(() {
      mockDatabase = MockAppDatabase();
      mockApiService = MockApiService();
    });

    ProviderContainer createContainer() {
      return ProviderContainer(
        overrides: [
          db.appDatabaseProvider.overrideWithValue(mockDatabase),
          apiServiceProvider.overrideWithValue(mockApiService),
          settingsProvider.overrideWith(FakeSettings.new),
          isOfflineProvider.overrideWithValue(false),
        ],
      );
    }

    tearDown(() {
      container.dispose();
    });

    db.Novel buildNovel(String ncode, {int? cachedAt}) {
      return db.Novel(ncode: ncode, cachedAt: cachedAt);
    }

    test('cachedAtが古い小説のみAPIから再取得する', () async {
      container = createContainer();
      final now = DateTime.now().millisecondsSinceEpoch;

      when(mockDatabase.getLibraryNovels()).thenAnswer(
        (_) async => [
          // 十分新しいためスキップされる
          buildNovel('n1111aa', cachedAt: now),
          // 古いため再取得対象
          buildNovel(
            'n2222bb',
            cachedAt: now - const Duration(hours: 10).inMilliseconds,
          ),
          // cachedAtがnullなので再取得対象
          buildNovel('n3333cc'),
        ],
      );
      when(
        mockApiService.fetchMultipleNovelsInfo(['n2222bb', 'n3333cc']),
      ).thenAnswer((_) async => {});

      final repository = container.read(novelRepositoryProvider);
      await repository.refreshStaleLibraryMetadata();

      verify(
        mockApiService.fetchMultipleNovelsInfo(['n2222bb', 'n3333cc']),
      ).called(1);
    });

    test('再取得対象が無い場合はAPIを呼び出さない', () async {
      container = createContainer();
      final now = DateTime.now().millisecondsSinceEpoch;

      when(
        mockDatabase.getLibraryNovels(),
      ).thenAnswer((_) async => [buildNovel('n1111aa', cachedAt: now)]);

      final repository = container.read(novelRepositoryProvider);
      await repository.refreshStaleLibraryMetadata();

      verifyNever(mockApiService.fetchMultipleNovelsInfo(any));
    });

    test('APIが例外を投げても静かに終了する', () async {
      container = createContainer();

      when(
        mockDatabase.getLibraryNovels(),
      ).thenAnswer((_) async => [buildNovel('n1111aa')]);
      when(
        mockApiService.fetchMultipleNovelsInfo(['n1111aa']),
      ).thenThrow(Exception('network error'));

      final repository = container.read(novelRepositoryProvider);

      // 例外がスローされずに完了すればよい
      await repository.refreshStaleLibraryMetadata();
    });
  });
}

class FakeSettings extends Settings {
  @override
  Future<AppSettings> build() async {
    return const AppSettings(
      fontSize: 16,
      isVertical: false,
      themeMode: ThemeMode.system,
      lineHeight: 1.5,
      fontFamily: 'NotoSansJP',
      isIncognito: false,
      isPageFlip: false,
      isRubyEnabled: true,
    );
  }
}
