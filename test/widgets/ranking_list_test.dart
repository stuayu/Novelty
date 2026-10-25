import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:novel_parser_core/novel_parser_core.dart';
import 'package:novelty/domain/ranking_filter_state.dart';
import 'package:novelty/models/novel_info.dart';
import 'package:novelty/models/novel_search_query.dart';
import 'package:novelty/models/novel_search_result.dart';
import 'package:novelty/models/ranking_page.dart';
import 'package:novelty/providers/ranking_provider.dart';
import 'package:novelty/services/api_service.dart';
import 'package:novelty/sites/hameln/hameln_site.dart';
import 'package:novelty/sites/novel_site.dart';
import 'package:novelty/sites/novel_site_registry.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:novelty/utils/settings_provider.dart';
import 'package:novelty/widgets/ranking_list.dart';

import 'ranking_list_test.mocks.dart';

class _FailingSecondPageSite extends NovelSite {
  int requestCount = 0;
  int failedPageCount = 0;

  @override
  NovelSource get source => NovelSource.hameln;

  @override
  List<GenreMaster> get genres => const [];

  @override
  List<RankingTypeMaster> get rankingTypes => const [];

  @override
  String? metaText(NovelInfo info) => null;

  @override
  List<NovelContentElement> parseEpisodeBody(String html) =>
      throw UnsupportedError('テスト対象外');

  @override
  Future<RankingPage> fetchRanking(String rankingType, {int page = 1}) async {
    requestCount++;
    if (page == 1) {
      return RankingPage(
        novels: List.generate(
          20,
          (index) => NovelInfo(
            source: source,
            workId: 'work-$index',
            title: '作品$index',
            end: 1,
          ),
        ),
        hasNextPage: true,
      );
    }
    if (failedPageCount++ == 0) throw Exception('通信失敗');
    return const RankingPage(novels: [], hasNextPage: false);
  }
}

@GenerateMocks([ApiService])
void main() {
  group('RankingList Widget Tests', () {
    late MockApiService mockApiService;

    setUp(() {
      mockApiService = MockApiService();
    });

    testWidgets('アクセス制限時は待ってから再試行する説明を表示する', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            rankingProvider(
              NovelSource.hameln,
              'rank_day',
            ).overrideWithValue(
              const RankingState(
                error: HamelnCloudflareChallengeException(
                  'https://syosetu.org/?mode=rank_day',
                ),
              ),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: RankingList(
                source: NovelSource.hameln,
                rankingType: 'rank_day',
              ),
            ),
          ),
        ),
      );

      expect(
        find.text('アクセスが制限されています。しばらく待ってから再度お試しください'),
        findsOneWidget,
      );
      expect(find.text('読み込みに失敗しました'), findsNothing);
    });

    testWidgets('作品が0件でも次ページがあるときは追加読込を案内する', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            rankingProvider(
              NovelSource.hameln,
              'rank_day',
            ).overrideWithValue(
              const RankingState(page: 2),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: RankingList(
                source: NovelSource.hameln,
                rankingType: 'rank_day',
              ),
            ),
          ),
        ),
      );

      expect(find.text('次のページを読み込む'), findsOneWidget);
    });

    testWidgets('追加ページ取得の失敗を表示して再試行を案内する', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            rankingProvider(
              NovelSource.hameln,
              'rank_day',
            ).overrideWithValue(
              RankingState(
                novels: const [
                  NovelInfo(
                    source: NovelSource.hameln,
                    workId: '123',
                    title: '表示済み作品',
                  ),
                ],
                page: 3,
                error: Exception('通信失敗'),
              ),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: RankingList(
                source: NovelSource.hameln,
                rankingType: 'rank_day',
              ),
            ),
          ),
        ),
      );

      expect(find.text('続きの読み込みに失敗しました'), findsOneWidget);
      expect(find.text('再試行'), findsOneWidget);
    });

    testWidgets('空の結果で追加ページの取得に失敗しても再試行を案内する', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            rankingProvider(
              NovelSource.hameln,
              'rank_day',
            ).overrideWithValue(
              RankingState(
                page: 2,
                error: Exception('通信失敗'),
              ),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: RankingList(
                source: NovelSource.hameln,
                rankingType: 'rank_day',
              ),
            ),
          ),
        ),
      );

      expect(find.text('続きの読み込みに失敗しました'), findsOneWidget);
      expect(find.text('再試行'), findsOneWidget);
    });

    testWidgets('追加読み込み失敗後はスクロールで再要求せず明示的な再試行を待つ', (
      tester,
    ) async {
      final site = _FailingSecondPageSite();
      await tester.binding.setSurfaceSize(const Size(390, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            novelSiteRegistryProvider.overrideWithValue({
              NovelSource.hameln: site,
            }),
            isOfflineModeProvider.overrideWithValue(false),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: RankingList(
                source: NovelSource.hameln,
                rankingType: 'rank_day',
              ),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(site.requestCount, 1);

      await tester.drag(find.byType(ListView), const Offset(0, -5000));
      await tester.pumpAndSettle();
      expect(site.requestCount, 2);
      expect(find.text('続きの読み込みに失敗しました'), findsOneWidget);

      final listFinder = find.byType(ListView);
      final scrollableFinder = find.descendant(
        of: listFinder,
        matching: find.byType(Scrollable),
      );
      final offsetBeforeRetryScroll = tester
          .state<ScrollableState>(scrollableFinder)
          .position
          .pixels;
      await tester.drag(listFinder, const Offset(0, 400));
      await tester.pumpAndSettle();
      expect(
        tester.state<ScrollableState>(scrollableFinder).position.pixels,
        lessThan(offsetBeforeRetryScroll),
      );
      await tester.drag(listFinder, const Offset(0, -1000));
      await tester.pumpAndSettle();
      expect(site.requestCount, 2);

      await tester.ensureVisible(find.text('再試行'));
      await tester.tap(find.text('再試行'));
      await tester.pumpAndSettle();
      expect(site.requestCount, 3);
    });

    testWidgets('should display ranking list items', (
      tester,
    ) async {
      final mockNovels = List.generate(
        5,
        (index) => NovelInfo(
          ncode: 'n$index',
          title: 'Novel $index',
          writer: 'Writer $index',
          story: 'Story $index',
          genreId: '101',
          novelType: 1,
          end: 1,
          allPoint: 1000 - index,
        ),
      );

      final searchResult = NovelSearchResult(
        novels: mockNovels,
        allCount: 5,
      );

      // デフォルトクエリ一致
      when(
        mockApiService.searchNovels(any),
      ).thenAnswer((_) async => searchResult);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // ignore: scoped_providers_should_specify_dependencies overrides_are_scoped_to_test
            apiServiceProvider.overrideWithValue(mockApiService),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: RankingList(
                source: NovelSource.narou,
                rankingType: 'd',
                key: PageStorageKey('test'),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Novel 0'), findsOneWidget);
      expect(find.text('Novel 4'), findsOneWidget);
      expect(find.byType(ListView), findsOneWidget);
    });

    testWidgets('should update query when filter changes', (
      tester,
    ) async {
      final mockNovels = [
        const NovelInfo(
          ncode: 'n1',
          title: 'Filtered Novel',
          writer: 'Writer',
          genreId: '201', // ファンタジー
        ),
      ];

      final searchResult = NovelSearchResult(
        novels: mockNovels,
        allCount: 1,
      );

      when(
        mockApiService.searchNovels(any),
      ).thenAnswer((_) async => searchResult);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // ignore: scoped_providers_should_specify_dependencies overrides_are_scoped_to_test
            apiServiceProvider.overrideWithValue(mockApiService),
            // ignore: scoped_providers_should_specify_dependencies overrides_are_scoped_to_test
            rankingFilterStateProvider(
              NovelSource.narou,
              'd',
            ).overrideWithValue(
              const RankingFilterState(selectedGenreId: '201'),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: RankingList(
                source: NovelSource.narou,
                rankingType: 'd',
                key: PageStorageKey('test_filter'),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // searchNovels がジャンルを含むクエリで呼ばれたことを確認
      final captured = verify(mockApiService.searchNovels(captureAny)).captured;
      final query = captured.last as NovelSearchQuery;
      expect(query.genreId, equals(['201']));

      expect(find.text('Filtered Novel'), findsOneWidget);
    });
    testWidgets('should filter ongoing novels locally', (
      tester,
    ) async {
      final mockNovels = [
        const NovelInfo(
          ncode: 'n1',
          title: 'Ongoing Novel',
          writer: 'Writer',
          novelType: 1, // 連載中
          end: 1, // 連載中
        ),
        const NovelInfo(
          ncode: 'n2',
          title: 'Short Story',
          writer: 'Writer',
          novelType: 2, // 短編
          end: 0, // 短編または完結
        ),
      ];

      final searchResult = NovelSearchResult(
        novels: mockNovels,
        allCount: 2,
      );

      when(
        mockApiService.searchNovels(any),
      ).thenAnswer((_) async => searchResult);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // ignore: scoped_providers_should_specify_dependencies overrides_are_scoped_to_test
            apiServiceProvider.overrideWithValue(mockApiService),
            // ignore: scoped_providers_should_specify_dependencies overrides_are_scoped_to_test
            rankingFilterStateProvider(
              NovelSource.narou,
              'd',
            ).overrideWithValue(
              const RankingFilterState(showOnlyOngoing: true),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: RankingList(
                source: NovelSource.narou,
                rankingType: 'd',
                key: PageStorageKey('test_ongoing_local'),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // クエリに type='r' が含まれないことを確認（削除したため）
      final captured = verify(mockApiService.searchNovels(captureAny)).captured;
      final query = captured.last as NovelSearchQuery;
      expect(query.type, isNull);

      // フィルタリング検証: 連載中の小説のみ表示されること
      expect(find.text('Ongoing Novel'), findsOneWidget);
      expect(find.text('Short Story'), findsNothing);
    });
    testWidgets('should refresh list when filter changes dynamically', (
      tester,
    ) async {
      final mockNovels = [
        const NovelInfo(
          ncode: 'n1',
          title: 'Initial Novel',
          writer: 'Writer',
          novelType: 1,
          end: 1,
        ),
      ];
      final filteredNovels = [
        const NovelInfo(
          ncode: 'n2',
          title: 'Filtered Novel',
          writer: 'Writer',
          novelType: 1,
          end: 1,
        ),
      ];

      when(mockApiService.searchNovels(any)).thenAnswer(
        (_) async => NovelSearchResult(novels: mockNovels, allCount: 1),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // ignore: scoped_providers_should_specify_dependencies overrides_are_scoped_to_test
            apiServiceProvider.overrideWithValue(mockApiService),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: RankingList(
                source: NovelSource.narou,
                rankingType: 'd',
                key: PageStorageKey('test_dynamic'),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Initial Novel'), findsOneWidget);

      // フィルタを変更
      final element = tester.element(find.byType(RankingList));
      final container = ProviderScope.containerOf(element);
      container
          .read(rankingFilterStateProvider(NovelSource.narou, 'd').notifier)
          .setShowOnlyOngoing(value: true);

      // 新しいクエリ用にモックの応答を更新
      when(mockApiService.searchNovels(any)).thenAnswer(
        (_) async => NovelSearchResult(novels: filteredNovels, allCount: 1),
      );

      await tester.pumpAndSettle();

      // 絞り込み後の小説が表示されるはず
      // リアクティブ性が無い場合、'Initial Novel' が表示されたままになり失敗する
      if (find.text('Filtered Novel').evaluate().isEmpty) {}
      expect(find.text('Filtered Novel'), findsOneWidget);
    });
  });
}
