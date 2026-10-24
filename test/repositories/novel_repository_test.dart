import 'package:dio/dio.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:narou_parser/narou_parser.dart';
import 'package:novelty/database/database.dart' as db;
import 'package:novelty/models/episode.dart';
import 'package:novelty/models/novel_info.dart';
import 'package:novelty/providers/network_fallback_event_provider.dart';
import 'package:novelty/repositories/novel_repository.dart';
import 'package:novelty/services/api_service.dart';
import 'package:novelty/sites/novel_site.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:novelty/utils/ncode_utils.dart';
import 'package:novelty/utils/settings_provider.dart';

import '../providers/novel_info_offline_test.mocks.dart';

class _DownloadApiService extends ApiService {
  _DownloadApiService(this._novelInfo);

  final NovelInfo _novelInfo;
  int metadataFetchCount = 0;
  final List<NovelInfo?> episodeMetadata = <NovelInfo?>[];

  @override
  Future<NovelInfo> fetchNovelInfo(String ncode) async {
    metadataFetchCount++;
    return _novelInfo;
  }

  @override
  Future<Episode> fetchEpisode(
    String ncode,
    int episode, {
    NovelInfo? novelInfo,
  }) async {
    episodeMetadata.add(novelInfo);
    return Episode(
      ncode: ncode,
      index: episode,
      subtitle: '第$episode話',
      body: '<p>本文</p>',
    );
  }
}

class _RateLimitedApiService extends ApiService {
  _RateLimitedApiService({this.statusCode = 429});

  final int statusCode;
  int episodeRequestCount = 0;

  @override
  Future<NovelInfo> fetchNovelInfo(String ncode) async => NovelInfo(
    ncode: ncode,
    title: '制限テスト',
    novelType: 1,
    episodes: [
      const Episode(index: 1, revised: 'r1'),
      const Episode(index: 2, revised: 'r2'),
    ],
  );

  @override
  Future<Episode> fetchEpisode(
    String ncode,
    int episode, {
    NovelInfo? novelInfo,
  }) async {
    episodeRequestCount++;
    final request = RequestOptions(path: 'https://api.syosetu.com/episode');
    throw DioException(
      requestOptions: request,
      response: Response<dynamic>(
        requestOptions: request,
        statusCode: statusCode,
      ),
    );
  }
}

class _MetadataRateLimitedApiService extends ApiService {
  int episodeRequestCount = 0;

  @override
  Future<NovelInfo> fetchNovelInfo(String ncode) async {
    final request = RequestOptions(path: 'https://api.syosetu.com/novel');
    throw DioException(
      requestOptions: request,
      response: Response<dynamic>(requestOptions: request, statusCode: 429),
    );
  }

  @override
  Future<Episode> fetchEpisode(
    String ncode,
    int episode, {
    NovelInfo? novelInfo,
  }) async {
    episodeRequestCount++;
    return Episode(index: episode, body: '<p>本文</p>');
  }
}

class _DownloadTestKakuyomuSite extends NovelSite {
  _DownloadTestKakuyomuSite({
    required this.workId,
    required this.totalEpisodes,
    this.infoFailure,
    this.tocFailure,
  });

  final String workId;
  final int totalEpisodes;
  final Exception? infoFailure;
  final Exception? tocFailure;
  int infoFetchCount = 0;
  int tocFetchCount = 0;
  int episodeFetchCount = 0;
  final List<String?> episodeFetchUrls = <String?>[];

  @override
  NovelSource get source => NovelSource.kakuyomu;

  @override
  List<GenreMaster> get genres => const <GenreMaster>[];

  @override
  List<RankingTypeMaster> get rankingTypes => const <RankingTypeMaster>[];

  @override
  String? metaText(NovelInfo info) => null;

  @override
  Future<NovelInfo> fetchNovelInfo(String workId) async {
    infoFetchCount++;
    if (infoFailure case final failure?) throw failure;
    return NovelInfo(
      source: NovelSource.kakuyomu,
      workId: workId,
      title: '制限テスト',
      generalAllNo: totalEpisodes,
    );
  }

  @override
  Future<List<Episode>> fetchToc(String workId) async {
    tocFetchCount++;
    if (tocFailure case final failure?) throw failure;
    return List<Episode>.generate(
      totalEpisodes,
      (index) => Episode(
        source: NovelSource.kakuyomu,
        index: index + 1,
        url: 'https://kakuyomu.jp/works/$workId/episodes/${index + 1}',
      ),
    );
  }

  @override
  Future<Episode> fetchEpisode(String workId, int index, {String? url}) async {
    episodeFetchCount++;
    episodeFetchUrls.add(url);
    return Episode(
      source: NovelSource.kakuyomu,
      index: index,
      subtitle: '第$index話',
      body: '<p>本文</p>',
      url: url,
    );
  }
}

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
          isOfflineModeProvider.overrideWithValue(isOffline),
        ],
      );
    }

    tearDown(() {
      container.dispose();
    });

    const testNcode = 'n1234ab';
    final normalizedNcode = testNcode.toNormalizedNcode();
    const page = 1;

    test('should return cached episodes when offline', () async {
      container = createContainer(isOffline: true); // Offline

      when(
        mockDatabase.getEpisodesRange(
          NovelSource.narou,
          normalizedNcode,
          1,
          100,
        ),
      ).thenAnswer(
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
      final result = await repository.fetchEpisodeList(
        NovelSource.narou,
        testNcode,
        page,
      );

      expect(result.length, 1);
      expect(result.first.subtitle, 'Ep 1');
      verify(
        mockDatabase.getEpisodesRange(
          NovelSource.narou,
          normalizedNcode,
          1,
          100,
        ),
      ).called(1);
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
      final result = await repository.fetchEpisodeList(
        NovelSource.narou,
        testNcode,
        page,
      );

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

      when(
        mockDatabase.getEpisodesRange(
          NovelSource.narou,
          normalizedNcode,
          1,
          100,
        ),
      ).thenAnswer(
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
      final result = await repository.fetchEpisodeList(
        NovelSource.narou,
        testNcode,
        page,
      );

      expect(result.length, 1);
      expect(result.first.subtitle, 'Ep 1');
      verify(mockApiService.fetchEpisodeList(normalizedNcode, page)).called(1);
      verify(
        mockDatabase.getEpisodesRange(
          NovelSource.narou,
          normalizedNcode,
          1,
          100,
        ),
      ).called(1);
    });
  });

  group('NovelRepository watchNovelInfo', () {
    const testNcode = 'n1234ab';
    final normalizedNcode = testNcode.toNormalizedNcode();

    late db.AppDatabase database;
    late MockApiService mockApiService;
    late ProviderContainer container;
    NetworkFallbackEventData? fallbackEvent;

    setUp(() {
      database = db.AppDatabase.memory();
      mockApiService = MockApiService();
      container =
          ProviderContainer(
            overrides: [
              db.appDatabaseProvider.overrideWithValue(database),
              apiServiceProvider.overrideWithValue(mockApiService),
              settingsProvider.overrideWith(FakeSettings.new),
              isOfflineModeProvider.overrideWithValue(false),
            ],
          )..listen(
            networkFallbackEventProvider,
            (_, next) => fallbackEvent = next,
            fireImmediately: true,
          );
      fallbackEvent = null;
    });

    tearDown(() async {
      container.dispose();
      await database.close();
    });

    Future<void> insertCachedNovel({
      required String title,
      bool isPrivate = false,
    }) async {
      await database.insertNovel(
        NovelInfo(
          ncode: normalizedNcode,
          title: title,
        ).toDbCompanion().copyWith(
          cachedAt: drift.Value(DateTime.now().millisecondsSinceEpoch),
          isPrivate: drift.Value(isPrivate),
        ),
      );
    }

    test('キャッシュがあれば即座に発行し、裏で最新を取得して更新する', () async {
      await insertCachedNovel(title: 'cached title');

      when(mockApiService.fetchNovelInfo(normalizedNcode)).thenAnswer(
        (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return NovelInfo(
            ncode: normalizedNcode,
            title: 'fresh title',
          );
        },
      );

      final repository = container.read(novelRepositoryProvider);
      final stream = repository.watchNovelInfo(NovelSource.narou, testNcode);

      await expectLater(
        stream,
        emitsInOrder([
          predicate<NovelInfo>((info) => info.title == 'cached title'),
          predicate<NovelInfo>((info) => info.title == 'fresh title'),
        ]),
      );
      verify(mockApiService.fetchNovelInfo(normalizedNcode)).called(1);
    });

    test('API失敗時はキャッシュを維持し、フォールバックイベントを発行する', () async {
      await insertCachedNovel(title: 'cached title');

      when(
        mockApiService.fetchNovelInfo(normalizedNcode),
      ).thenThrow(Exception('network error'));

      final repository = container.read(novelRepositoryProvider);
      final stream = repository.watchNovelInfo(NovelSource.narou, testNcode);

      await expectLater(
        stream,
        emits(
          predicate<NovelInfo>((info) => info.title == 'cached title'),
        ),
      );
      verify(mockApiService.fetchNovelInfo(normalizedNcode)).called(1);
      expect(
        fallbackEvent?.message,
        '最新の作品情報を取得できませんでした。キャッシュを表示しています。',
      );
    });

    test('非公開作品と判定されたらisPrivateフラグを立ててキャッシュを維持', () async {
      await insertCachedNovel(title: 'cached title');

      when(
        mockApiService.fetchNovelInfo(normalizedNcode),
      ).thenThrow(const NovelNotFoundException());

      final repository = container.read(novelRepositoryProvider);
      final stream = repository.watchNovelInfo(NovelSource.narou, testNcode);

      await expectLater(
        stream,
        emits(
          predicate<NovelInfo>((info) => info.title == 'cached title'),
        ),
      );

      final novel = await database.getNovel(NovelSource.narou, normalizedNcode);
      expect(novel?.isPrivate, isTrue);
    });

    test('キャッシュが無い状態で取得成功ならデータを返す', () async {
      when(mockApiService.fetchNovelInfo(normalizedNcode)).thenAnswer(
        (_) async => NovelInfo(
          ncode: normalizedNcode,
          title: 'fresh title',
        ),
      );

      final repository = container.read(novelRepositoryProvider);
      final stream = repository.watchNovelInfo(NovelSource.narou, testNcode);

      await expectLater(
        stream,
        emits(
          predicate<NovelInfo>((info) => info.title == 'fresh title'),
        ),
      );
      verify(mockApiService.fetchNovelInfo(normalizedNcode)).called(1);
    });

    test('キャッシュが無い状態で非公開作品と判定された場合、プレースホルダーが挿入される', () async {
      when(
        mockApiService.fetchNovelInfo(normalizedNcode),
      ).thenThrow(const NovelNotFoundException());

      final repository = container.read(novelRepositoryProvider);
      final stream = repository.watchNovelInfo(NovelSource.narou, testNcode);

      await expectLater(
        stream,
        emits(
          predicate<NovelInfo>(
            (info) =>
                info.workId == normalizedNcode &&
                info.title == null &&
                info.isPrivate,
          ),
        ),
      );

      final novel = await database.getNovel(NovelSource.narou, normalizedNcode);
      expect(novel, isNotNull);
      expect(novel!.isPrivate, isTrue);
      expect(novel.cachedAt, isNotNull);
    });

    test('キャッシュが無い状態でネットワークエラー時はストリームエラーとして伝播する', () async {
      when(
        mockApiService.fetchNovelInfo(normalizedNcode),
      ).thenThrow(Exception('network error'));

      final repository = container.read(novelRepositoryProvider);
      final stream = repository.watchNovelInfo(NovelSource.narou, testNcode);

      await expectLater(
        stream,
        emitsError(
          predicate<Exception>((e) => e.toString().contains('network error')),
        ),
      );

      final novel = await database.getNovel(NovelSource.narou, normalizedNcode);
      expect(novel, isNull);
    });

    test('オフラインかつキャッシュが無い場合はOfflineExceptionを投げる', () async {
      container.dispose();
      container =
          ProviderContainer(
            overrides: [
              db.appDatabaseProvider.overrideWithValue(database),
              apiServiceProvider.overrideWithValue(mockApiService),
              settingsProvider.overrideWith(FakeSettings.new),
              isOfflineModeProvider.overrideWithValue(true),
            ],
          )..listen(
            networkFallbackEventProvider,
            (_, _) {},
          );

      final repository = container.read(novelRepositoryProvider);
      final stream = repository.watchNovelInfo(NovelSource.narou, testNcode);

      await expectLater(
        stream,
        emitsError(isA<OfflineException>()),
      );
      verifyNever(mockApiService.fetchNovelInfo(any));
    });
  });

  group('NovelRepository downloadSingleEpisode', () {
    const testNcode = 'n1234ab';
    final normalizedNcode = testNcode.toNormalizedNcode();
    const episodeId = 1;

    late db.AppDatabase database;
    late MockApiService mockApiService;
    late ProviderContainer container;

    setUp(() {
      database = db.AppDatabase.memory();
      mockApiService = MockApiService();
      container = ProviderContainer(
        overrides: [
          db.appDatabaseProvider.overrideWithValue(database),
          apiServiceProvider.overrideWithValue(mockApiService),
          settingsProvider.overrideWith(FakeSettings.new),
          isOfflineModeProvider.overrideWithValue(false),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      await database.close();
    });

    test('フェッチ失敗時に既存の目次サブタイトルが上書きされない', () async {
      await database.insertNovel(
        NovelInfo(ncode: normalizedNcode, title: 'test').toDbCompanion(),
      );
      await database.upsertEpisodes([
        db.EpisodeListEntriesCompanion(
          source: const drift.Value(NovelSource.narou),
          workId: drift.Value(normalizedNcode),
          episodeId: const drift.Value(episodeId),
          subtitle: const drift.Value('元のサブタイトル'),
          url: const drift.Value('https://example.com/1/'),
        ),
      ]);

      when(
        mockApiService.fetchEpisode(normalizedNcode, episodeId),
      ).thenThrow(Exception('network error'));

      final repository = container.read(novelRepositoryProvider);
      final result = await repository.downloadSingleEpisode(
        NovelSource.narou,
        testNcode,
        episodeId,
      );

      expect(result, isFalse);

      final data = await database.getEpisodeData(
        NovelSource.narou,
        normalizedNcode,
        episodeId,
      );
      expect(data?.subtitle, '元のサブタイトル');
      expect(data?.content, isEmpty);
    });
  });

  group('NovelRepository downloadNovel メタデータ再利用', () {
    const ncode = 'n1234ab';
    late db.AppDatabase database;
    late _DownloadApiService apiService;
    late ProviderContainer container;

    setUp(() {
      database = db.AppDatabase.memory();
      apiService = _DownloadApiService(
        const NovelInfo(
          ncode: ncode,
          title: 'まとめて取得する作品',
          novelType: 1,
          episodes: [
            Episode(index: 1, revised: 'r1'),
            Episode(index: 2, revised: 'r2'),
          ],
        ),
      );
      container = ProviderContainer(
        overrides: [
          db.appDatabaseProvider.overrideWithValue(database),
          apiServiceProvider.overrideWithValue(apiService),
          settingsProvider.overrideWith(FakeSettings.new),
          isOfflineModeProvider.overrideWithValue(false),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      await database.close();
    });

    test('取得済みNovelInfoを各エピソードへ渡して再問い合わせを避ける', () async {
      final repository = container.read(novelRepositoryProvider);

      await repository.downloadNovel(NovelSource.narou, ncode, 2);

      expect(apiService.metadataFetchCount, 1);
      expect(apiService.episodeMetadata, hasLength(2));
      expect(apiService.episodeMetadata, everyElement(isNotNull));
      expect(
        apiService.episodeMetadata,
        everyElement(apiService.episodeMetadata.first),
      );
    });
  });

  group('NovelRepository downloadNovel 429中断', () {
    late db.AppDatabase database;
    late ProviderContainer container;

    setUp(() {
      database = db.AppDatabase.memory();
    });

    tearDown(() async {
      container.dispose();
      await database.close();
    });

    ProviderContainer createContainer({
      required ApiService apiService,
      required NovelSite kakuyomuSite,
    }) => ProviderContainer(
      overrides: [
        db.appDatabaseProvider.overrideWithValue(database),
        apiServiceProvider.overrideWithValue(apiService),
        settingsProvider.overrideWith(FakeSettings.new),
        isOfflineModeProvider.overrideWithValue(false),
        novelRepositoryProvider.overrideWith(
          (ref) => NovelRepository(
            ref: ref,
            apiService: apiService,
            settings: ref.watch(settingsProvider),
            db: database,
            sites: <NovelSource, NovelSite>{
              NovelSource.kakuyomu: kakuyomuSite,
            },
          ),
        ),
      ],
    );

    test('なろうの本文取得で429を受けたら失敗を記録して後続話を止める', () async {
      const ncode = 'n1234ab';
      final api = _RateLimitedApiService();
      final site = _DownloadTestKakuyomuSite(
        workId: 'work',
        totalEpisodes: 1,
      );
      container = createContainer(apiService: api, kakuyomuSite: site);
      final repository = container.read(novelRepositoryProvider);
      final progressFuture = repository
          .watchDownloadProgress(NovelSource.narou, ncode)
          .toList();

      await expectLater(
        repository.downloadNovel(NovelSource.narou, ncode, 2),
        throwsA(isA<DioException>()),
      );

      final progress = await progressFuture;
      expect(api.episodeRequestCount, 1);
      expect(progress.last.isDownloading, isFalse);
      expect(progress.last.errorMessage, isNotNull);
      final failedEpisode = await database.getEpisodeData(
        NovelSource.narou,
        ncode,
        1,
      );
      expect(failedEpisode?.content, isEmpty);
    });

    test('なろうの作品情報取得で429を受けたら本文取得へ進まず中断する', () async {
      const ncode = 'n1234ab';
      final api = _MetadataRateLimitedApiService();
      final site = _DownloadTestKakuyomuSite(
        workId: 'work',
        totalEpisodes: 1,
      );
      container = createContainer(apiService: api, kakuyomuSite: site);
      final repository = container.read(novelRepositoryProvider);
      final progressFuture = repository
          .watchDownloadProgress(NovelSource.narou, ncode)
          .toList();

      await expectLater(
        repository.downloadNovel(NovelSource.narou, ncode, 2),
        throwsA(isA<DioException>()),
      );

      final progress = await progressFuture;
      expect(api.episodeRequestCount, 0);
      expect(progress.last.isDownloading, isFalse);
      expect(progress.last.errorMessage, isNotNull);
    });

    test('なろうの本文取得で403を受けた場合は後続話も試す', () async {
      const ncode = 'n1234ab';
      final api = _RateLimitedApiService(statusCode: 403);
      final site = _DownloadTestKakuyomuSite(
        workId: 'work',
        totalEpisodes: 1,
      );
      container = createContainer(apiService: api, kakuyomuSite: site);
      final repository = container.read(novelRepositoryProvider);
      final progressFuture = repository
          .watchDownloadProgress(NovelSource.narou, ncode)
          .toList();

      await repository.downloadNovel(NovelSource.narou, ncode, 2);

      final progress = await progressFuture;
      expect(api.episodeRequestCount, 2);
      expect(progress.last.isDownloading, isFalse);
      expect(progress.last.errorMessage, contains('2話'));
    });

    test('カクヨム目次取得時のDio 429で本文リクエストへ進まない', () async {
      const workId = 'work';
      final requestOptions = RequestOptions(
        path: 'https://kakuyomu.jp/works/$workId/episode_sidebar',
      );
      final site = _DownloadTestKakuyomuSite(
        workId: workId,
        totalEpisodes: 2,
        tocFailure: DioException(
          requestOptions: requestOptions,
          response: Response<dynamic>(
            requestOptions: requestOptions,
            statusCode: 429,
          ),
        ),
      );
      container = createContainer(apiService: ApiService(), kakuyomuSite: site);
      final repository = container.read(novelRepositoryProvider);
      final progressFuture = repository
          .watchDownloadProgress(NovelSource.kakuyomu, workId)
          .toList();

      await expectLater(
        repository.downloadNovel(NovelSource.kakuyomu, workId, 2),
        throwsA(
          isA<DioException>().having(
            (error) => error.response?.statusCode,
            'statusCode',
            429,
          ),
        ),
      );

      final progress = await progressFuture;
      expect(site.tocFetchCount, 1);
      expect(site.episodeFetchCount, 0);
      expect(progress.last.isDownloading, isFalse);
      expect(progress.last.errorMessage, isNotNull);
    });

    test('カクヨム一括取得では作品情報を取得せず目次取得へ進む', () async {
      const workId = 'work';
      final site = _DownloadTestKakuyomuSite(
        workId: workId,
        totalEpisodes: 2,
        infoFailure: Exception('Kakuyomu work info should not be fetched'),
      );
      container = createContainer(apiService: ApiService(), kakuyomuSite: site);
      final repository = container.read(novelRepositoryProvider);
      final progressFuture = repository
          .watchDownloadProgress(NovelSource.kakuyomu, workId)
          .toList();

      await repository.downloadNovel(NovelSource.kakuyomu, workId, 2);

      final progress = await progressFuture;
      expect(site.infoFetchCount, 0);
      expect(site.tocFetchCount, 1);
      expect(site.episodeFetchCount, 2);
      expect(progress.last.isDownloading, isFalse);
      expect(progress.last.errorMessage, isNull);
    });

    test('カクヨム一括取得で一部URLが欠けていれば目次を1回だけ取得して補完する', () async {
      const workId = 'work';
      await database.upsertEpisodes([
        const db.EpisodeListEntriesCompanion(
          source: drift.Value(NovelSource.kakuyomu),
          workId: drift.Value(workId),
          episodeId: drift.Value(1),
          url: drift.Value('https://kakuyomu.jp/works/work/episodes/1'),
        ),
        const db.EpisodeListEntriesCompanion(
          source: drift.Value(NovelSource.kakuyomu),
          workId: drift.Value(workId),
          episodeId: drift.Value(2),
          url: drift.Value(null),
        ),
      ]);
      final site = _DownloadTestKakuyomuSite(
        workId: workId,
        totalEpisodes: 2,
      );
      container = createContainer(apiService: ApiService(), kakuyomuSite: site);
      final repository = container.read(novelRepositoryProvider);

      await repository.downloadNovel(NovelSource.kakuyomu, workId, 2);

      expect(site.tocFetchCount, 1);
      expect(site.episodeFetchUrls, hasLength(2));
      expect(site.episodeFetchUrls, everyElement(isNotNull));
      expect(
        await database.getEpisodeUrl(NovelSource.kakuyomu, workId, 2),
        'https://kakuyomu.jp/works/work/episodes/2',
      );
    });

    test('カクヨム一括取得で全URLがキャッシュ済みなら目次を再取得しない', () async {
      const workId = 'work';
      await database.upsertEpisodes(
        List<db.EpisodeListEntriesCompanion>.generate(
          2,
          (index) => db.EpisodeListEntriesCompanion(
            source: const drift.Value(NovelSource.kakuyomu),
            workId: const drift.Value(workId),
            episodeId: drift.Value(index + 1),
            url: drift.Value(
              'https://kakuyomu.jp/works/work/episodes/${index + 1}',
            ),
          ),
        ),
      );
      final site = _DownloadTestKakuyomuSite(
        workId: workId,
        totalEpisodes: 2,
      );
      container = createContainer(apiService: ApiService(), kakuyomuSite: site);
      final repository = container.read(novelRepositoryProvider);

      await repository.downloadNovel(NovelSource.kakuyomu, workId, 2);

      expect(site.tocFetchCount, 0);
      expect(site.episodeFetchUrls, hasLength(2));
      expect(site.episodeFetchUrls, everyElement(isNotNull));
    });
  });

  group('NovelRepository watchEpisodeList', () {
    const testNcode = 'n1234ab';
    final normalizedNcode = testNcode.toNormalizedNcode();
    const page = 1;

    late db.AppDatabase database;
    late MockApiService mockApiService;
    late ProviderContainer container;
    NetworkFallbackEventData? fallbackEvent;

    setUp(() {
      database = db.AppDatabase.memory();
      mockApiService = MockApiService();
      container =
          ProviderContainer(
            overrides: [
              db.appDatabaseProvider.overrideWithValue(database),
              apiServiceProvider.overrideWithValue(mockApiService),
              settingsProvider.overrideWith(FakeSettings.new),
              isOfflineModeProvider.overrideWithValue(false),
            ],
          )..listen(
            networkFallbackEventProvider,
            (_, next) => fallbackEvent = next,
            fireImmediately: true,
          );
      fallbackEvent = null;
    });

    tearDown(() async {
      container.dispose();
      await database.close();
    });

    Future<void> insertNovelAndEpisodes() async {
      await database.insertNovel(
        NovelInfo(ncode: normalizedNcode, title: 'test').toDbCompanion(),
      );
      await database
          .into(database.episodeListEntries)
          .insert(
            db.EpisodeListEntriesCompanion(
              source: const drift.Value(NovelSource.narou),
              workId: drift.Value(normalizedNcode),
              episodeId: const drift.Value(1),
              subtitle: const drift.Value('cached ep'),
              url: const drift.Value('http://example.com/1/'),
              fetchedAt: drift.Value(DateTime.now().millisecondsSinceEpoch),
            ),
          );
    }

    test('キャッシュがあれば即座に発行し、裏で最新を取得して更新する', () async {
      await insertNovelAndEpisodes();

      when(
        mockApiService.fetchEpisodeList(normalizedNcode, page),
      ).thenAnswer(
        (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return [
            const Episode(
              ncode: 'n1234ab',
              index: 1,
              subtitle: 'fresh ep',
              url: 'http://example.com/1/',
            ),
          ];
        },
      );

      final repository = container.read(novelRepositoryProvider);
      final stream = repository.watchEpisodeList(
        NovelSource.narou,
        testNcode,
        page,
      );

      await expectLater(
        stream,
        emitsInOrder([
          predicate<List<Episode>>(
            (list) => list.single.subtitle == 'cached ep',
          ),
          predicate<List<Episode>>(
            (list) => list.single.subtitle == 'fresh ep',
          ),
        ]),
      );
      verify(mockApiService.fetchEpisodeList(normalizedNcode, page)).called(1);
    });

    test('API失敗時はキャッシュ目次を維持し、フォールバックイベントを発行する', () async {
      await insertNovelAndEpisodes();

      when(
        mockApiService.fetchEpisodeList(normalizedNcode, page),
      ).thenThrow(Exception('network error'));

      final repository = container.read(novelRepositoryProvider);
      final stream = repository.watchEpisodeList(
        NovelSource.narou,
        testNcode,
        page,
      );

      await expectLater(
        stream,
        emits(
          predicate<List<Episode>>(
            (list) => list.single.subtitle == 'cached ep',
          ),
        ),
      );
      verify(mockApiService.fetchEpisodeList(normalizedNcode, page)).called(1);
      expect(
        fallbackEvent?.message,
        '最新の目次を取得できませんでした。キャッシュを表示しています。',
      );
    });

    test('キャッシュが無い状態で取得成功なら目次を返す', () async {
      await database.insertNovel(
        NovelInfo(ncode: normalizedNcode, title: 'test').toDbCompanion(),
      );

      when(
        mockApiService.fetchEpisodeList(normalizedNcode, page),
      ).thenAnswer(
        (_) async => [
          const Episode(
            ncode: 'n1234ab',
            index: 1,
            subtitle: 'fresh ep',
            url: 'http://example.com/1/',
          ),
        ],
      );

      final repository = container.read(novelRepositoryProvider);
      final stream = repository.watchEpisodeList(
        NovelSource.narou,
        testNcode,
        page,
      );

      await expectLater(
        stream,
        emits(
          predicate<List<Episode>>(
            (list) => list.single.subtitle == 'fresh ep',
          ),
        ),
      );
    });

    test('キャッシュが無い状態でAPI失敗時はストリームエラーとして伝播する', () async {
      await database.insertNovel(
        NovelInfo(ncode: normalizedNcode, title: 'test').toDbCompanion(),
      );

      when(
        mockApiService.fetchEpisodeList(normalizedNcode, page),
      ).thenThrow(Exception('network error'));

      final repository = container.read(novelRepositoryProvider);
      final stream = repository.watchEpisodeList(
        NovelSource.narou,
        testNcode,
        page,
      );

      await expectLater(
        stream,
        emitsError(
          predicate<Exception>((e) => e.toString().contains('network error')),
        ),
      );
    });

    test('オフラインかつキャッシュが無い場合はOfflineExceptionを投げる', () async {
      container.dispose();
      container =
          ProviderContainer(
            overrides: [
              db.appDatabaseProvider.overrideWithValue(database),
              apiServiceProvider.overrideWithValue(mockApiService),
              settingsProvider.overrideWith(FakeSettings.new),
              isOfflineModeProvider.overrideWithValue(true),
            ],
          )..listen(
            networkFallbackEventProvider,
            (_, _) {},
          );
      await database.insertNovel(
        NovelInfo(ncode: normalizedNcode, title: 'test').toDbCompanion(),
      );

      final repository = container.read(novelRepositoryProvider);
      final stream = repository.watchEpisodeList(
        NovelSource.narou,
        testNcode,
        page,
      );

      await expectLater(
        stream,
        emitsError(isA<OfflineException>()),
      );
      verifyNever(mockApiService.fetchEpisodeList(any, any));
    });
  });

  group('NovelRepository getEpisode', () {
    const testNcode = 'n1234ab';
    final normalizedNcode = testNcode.toNormalizedNcode();
    const episodeId = 1;

    late db.AppDatabase database;
    late MockApiService mockApiService;
    late ProviderContainer container;
    NetworkFallbackEventData? fallbackEvent;

    setUp(() {
      database = db.AppDatabase.memory();
      mockApiService = MockApiService();
      container =
          ProviderContainer(
            overrides: [
              db.appDatabaseProvider.overrideWithValue(database),
              apiServiceProvider.overrideWithValue(mockApiService),
              settingsProvider.overrideWith(FakeSettings.new),
              isOfflineModeProvider.overrideWithValue(false),
            ],
          )..listen(
            networkFallbackEventProvider,
            (_, next) => fallbackEvent = next,
            fireImmediately: true,
          );
      fallbackEvent = null;
    });

    tearDown(() async {
      container.dispose();
      await database.close();
    });

    Future<void> insertEpisodeContent() async {
      await database.insertNovel(
        NovelInfo(ncode: normalizedNcode, title: 'test').toDbCompanion(),
      );
      await database.updateEpisodeContent(
        source: NovelSource.narou,
        workId: normalizedNcode,
        episodeId: episodeId,
        content: [NovelContentElement.plainText('cached body')],
        fetchedAt: DateTime.now().millisecondsSinceEpoch,
        revisedAt: '2024-01-01',
      );
    }

    test('改稿がなければキャッシュを返し通信しない', () async {
      await insertEpisodeContent();

      final repository = container.read(novelRepositoryProvider);
      final content = await repository.getEpisode(
        NovelSource.narou,
        normalizedNcode,
        episodeId,
        revised: '2024-01-01',
      );

      expect(content.first, isA<PlainText>());
      expect((content.first as PlainText).text, 'cached body');
      verifyNever(mockApiService.fetchEpisode(any, any));
    });

    test('改稿ありで取得失敗時はキャッシュを返しフォールバックイベントを発行する', () async {
      await insertEpisodeContent();

      when(
        mockApiService.fetchEpisode(normalizedNcode, episodeId),
      ).thenThrow(Exception('network error'));

      final repository = container.read(novelRepositoryProvider);
      final content = await repository.getEpisode(
        NovelSource.narou,
        normalizedNcode,
        episodeId,
        revised: '2024-02-01',
      );

      expect(content.first, isA<PlainText>());
      expect((content.first as PlainText).text, 'cached body');
      verify(mockApiService.fetchEpisode(normalizedNcode, episodeId)).called(1);
      expect(
        fallbackEvent?.message,
        '最新のエピソードを取得できませんでした。キャッシュを表示しています。',
      );
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
      isIncognito: false,
      isPageFlip: false,
      isRubyEnabled: true,
    );
  }
}
