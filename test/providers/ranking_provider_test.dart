import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:novelty/domain/ranking_filter_state.dart';
import 'package:novelty/models/novel_info.dart';
import 'package:novelty/models/novel_search_result.dart';
import 'package:novelty/models/ranking_page.dart';
import 'package:novelty/providers/ranking_provider.dart';
import 'package:novelty/services/api_service.dart';
import 'package:novelty/sites/novel_site.dart';
import 'package:novelty/sites/novel_site_registry.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:novelty/utils/settings_provider.dart';
import 'package:novelty/utils/value_wrapper.dart';
import 'package:novelty/widgets/ranking_list.dart';

import 'novel_info_offline_test.mocks.dart';

/// 固定の [RankingPage] を返すだけの最小のサイト実装。
///
/// ランキング以外のメソッドは [NovelSite] のデフォルト実装
/// （[UnsupportedError]）を使用する。
class _StubRankingSite extends NovelSite {
  _StubRankingSite(this._pages, {this.onFetch});

  /// ページ番号（1始まり）に対応する [RankingPage] の一覧。
  final List<RankingPage> _pages;

  /// 非同期応答の順序を制御するテスト用フック。
  final Future<RankingPage> Function(int page)? onFetch;

  /// fetchRanking が呼ばれた回数。
  int callCount = 0;

  @override
  NovelSource get source => NovelSource.kakuyomu;

  @override
  List<GenreMaster> get genres => const <GenreMaster>[];

  @override
  List<RankingTypeMaster> get rankingTypes => const <RankingTypeMaster>[];

  @override
  String? metaText(NovelInfo info) => null;

  @override
  Future<RankingPage> fetchRanking(
    String rankingType, {
    int page = 1,
  }) {
    callCount++;
    if (onFetch != null) return onFetch!(page);
    final index = (page - 1).clamp(0, _pages.length - 1);
    return Future<RankingPage>.value(_pages[index]);
  }
}

void main() {
  group('RankingState', () {
    test('デフォルト値が正しく設定される', () {
      const state = RankingState();

      expect(state.novels, isEmpty);
      expect(state.isLoading, isFalse);
      expect(state.isLoadingMore, isFalse);
      expect(state.hasMore, isTrue);
      expect(state.page, equals(1));
      expect(state.error, isNull);
    });

    test('コンストラクタでフィールドを設定できる', () {
      final state = RankingState(
        novels: const [NovelInfo(title: 'Test', ncode: 'n1234')],
        isLoading: true,
        isLoadingMore: true,
        hasMore: false,
        page: 2,
        error: Exception('error'),
      );

      expect(state.novels.length, equals(1));
      expect(state.isLoading, isTrue);
      expect(state.isLoadingMore, isTrue);
      expect(state.hasMore, isFalse);
      expect(state.page, equals(2));
      expect(state.error, isNotNull);
    });

    test('copyWithでフィールドを変更できる', () {
      const state = RankingState();

      final updated = state.copyWith(
        isLoading: true,
        page: 2,
      );

      expect(updated.isLoading, isTrue);
      expect(updated.page, equals(2));
      expect(updated.novels, isEmpty); // 変更されていない
    });

    test('copyWithでerrorを設定できる', () {
      const state = RankingState();

      final withError = state.copyWith(
        error: Value<Object?>(Exception('error')),
      );
      expect(withError.error, isNotNull);
    });

    test('copyWithでnovelsを変更できる', () {
      const state = RankingState();

      final newNovels = [
        const NovelInfo(title: 'Test', ncode: 'n1234'),
      ];
      final updated = state.copyWith(novels: newNovels);

      expect(updated.novels, equals(newNovels));
    });

    test('同じ値を持つインスタンスは等価', () {
      // novelsリストは比較対象外（NovelInfoの等価性がfreezed依存のため）
      const state1 = RankingState(
        isLoading: true,
        page: 2,
      );
      const state2 = RankingState(
        isLoading: true,
        page: 2,
      );

      expect(state1, equals(state2));
      expect(state1.hashCode, equals(state2.hashCode));
    });

    test('異なる値を持つインスタンスは非等価', () {
      const state1 = RankingState();
      const state2 = RankingState(page: 2);

      expect(state1, isNot(equals(state2)));
    });

    test('toStringが正しい形式を返す', () {
      const state = RankingState(
        isLoading: true,
        page: 2,
      );

      expect(
        state.toString(),
        contains('RankingState'),
      );
    });
  });

  group('RankingNotifier（破棄時の安全性）', () {
    test('なろう側でAからBを経て戻った後に旧Aの例外が状態を上書きしない', () async {
      final mockApiService = MockApiService();
      final responses = List<Completer<NovelSearchResult>>.generate(
        3,
        (_) => Completer<NovelSearchResult>(),
      );
      var callCount = 0;
      when(
        mockApiService.searchNovels(any),
      ).thenAnswer((_) => responses[callCount++].future);
      final container = ProviderContainer(
        overrides: [
          apiServiceProvider.overrideWithValue(mockApiService),
          isOfflineModeProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);

      final subscription = container.listen(
        rankingProvider(NovelSource.narou, 'm'),
        (_, _) {},
      );
      await Future<void>.delayed(Duration.zero);
      final setOngoing = container
          .read(rankingFilterStateProvider(NovelSource.narou, 'm').notifier)
          .setShowOnlyOngoing;
      setOngoing(value: true);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      setOngoing(value: false);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      responses[2].complete(
        const NovelSearchResult(
          novels: <NovelInfo>[NovelInfo(title: '最新作品', ncode: 'n3')],
          allCount: 1,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      responses[0].completeError(Exception('古いリクエストの失敗'));
      responses[1].complete(
        const NovelSearchResult(novels: <NovelInfo>[], allCount: 0),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final state = container.read(rankingProvider(NovelSource.narou, 'm'));
      expect(state.error, isNull);
      expect(state.novels.single.title, '最新作品');
      subscription.close();
    });

    test('プロバイダ破棄後にfetchNextPageが完了しても例外を投げない', () async {
      final mockApiService = MockApiService();
      final completer = Completer<NovelSearchResult>();
      when(
        mockApiService.searchNovels(any),
      ).thenAnswer((_) => completer.future);

      final container = ProviderContainer(
        overrides: [
          apiServiceProvider.overrideWithValue(mockApiService),
          isOfflineModeProvider.overrideWithValue(false),
        ],
      );

      // ランキングの購読を開始（fetchNextPageが走る）
      final subscription = container.listen(
        rankingProvider(NovelSource.narou, 'm'),
        (_, _) {},
      );
      // fetchNextPage がAPI await中になるまで進める
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      // タブ切替等でプロバイダが破棄される
      subscription.close();
      container.dispose();

      // APIレスポンスが遅れて返る（破棄後の完了）
      completer.complete(
        const NovelSearchResult(novels: [], allCount: 0),
      );
      await Future<void>.delayed(Duration.zero);

      // 例外が投げられていなければ成功（破棄後のstate更新でエラーにならない）
      verify(mockApiService.searchNovels(any)).called(1);
    });
  });

  group('RankingNotifier（カクヨムのサイト実装経路）', () {
    testWidgets('画面を満たさない結果でも次ページがある間は自動で続きが読まれる', (
      tester,
    ) async {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 240);
      final site = _StubRankingSite(const <RankingPage>[
        RankingPage(
          novels: <NovelInfo>[NovelInfo(title: '作品A', ncode: 'n1')],
          hasNextPage: true,
        ),
        RankingPage(
          novels: <NovelInfo>[NovelInfo(title: '作品B', ncode: 'n2')],
          hasNextPage: false,
        ),
      ]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            novelSiteRegistryProvider.overrideWithValue(
              <NovelSource, NovelSite>{NovelSource.kakuyomu: site},
            ),
            isOfflineModeProvider.overrideWithValue(false),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: RankingList(
                source: NovelSource.kakuyomu,
                rankingType: 'daily',
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(site.callCount, 2);
      expect(find.text('作品B'), findsOneWidget);
    });

    testWidgets('フィルタ結果が空でも空状態を表示する', (tester) async {
      final site = _StubRankingSite(const <RankingPage>[
        RankingPage(novels: <NovelInfo>[], hasNextPage: false),
      ]);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            novelSiteRegistryProvider.overrideWithValue(
              <NovelSource, NovelSite>{NovelSource.kakuyomu: site},
            ),
            isOfflineModeProvider.overrideWithValue(false),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: RankingList(
                source: NovelSource.kakuyomu,
                rankingType: 'daily',
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('該当する作品がありません'), findsOneWidget);
    });

    test('フィルタ後に空のページを読み飛ばして結果があるページまで取得する', () async {
      final site = _StubRankingSite(<RankingPage>[
        const RankingPage(
          novels: <NovelInfo>[
            NovelInfo(title: '完結作品', ncode: 'n1', end: 0),
          ],
          hasNextPage: true,
        ),
        const RankingPage(
          novels: <NovelInfo>[
            NovelInfo(title: '連載作品', ncode: 'n2', end: 1),
          ],
          hasNextPage: false,
        ),
      ]);
      final container = ProviderContainer(
        overrides: [
          novelSiteRegistryProvider.overrideWithValue(
            <NovelSource, NovelSite>{NovelSource.kakuyomu: site},
          ),
          isOfflineModeProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(
            rankingFilterStateProvider(NovelSource.kakuyomu, 'daily').notifier,
          )
          .setShowOnlyOngoing(value: true);

      final subscription = container.listen(
        rankingProvider(NovelSource.kakuyomu, 'daily'),
        (_, _) {},
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final state = container.read(
        rankingProvider(NovelSource.kakuyomu, 'daily'),
      );
      expect(state.novels.single.title, '連載作品');
      expect(site.callCount, 2);
      expect(state.hasMore, isFalse);
      subscription.close();
    });

    test('条件変更後に古いランキング応答が新しい結果を上書きしない', () async {
      final oldResponse = Completer<RankingPage>();
      final newResponse = Completer<RankingPage>();
      var fetchCount = 0;
      final site = _StubRankingSite(
        const <RankingPage>[],
        onFetch: (_) =>
            ++fetchCount == 1 ? oldResponse.future : newResponse.future,
      );
      final container = ProviderContainer(
        overrides: [
          novelSiteRegistryProvider.overrideWithValue(
            <NovelSource, NovelSite>{NovelSource.kakuyomu: site},
          ),
          isOfflineModeProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);

      final subscription = container.listen(
        rankingProvider(NovelSource.kakuyomu, 'daily'),
        (_, _) {},
      );
      await Future<void>.delayed(Duration.zero);
      container
          .read(
            rankingFilterStateProvider(NovelSource.kakuyomu, 'daily').notifier,
          )
          .setShowOnlyOngoing(value: true);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      newResponse.complete(
        const RankingPage(
          novels: <NovelInfo>[
            NovelInfo(title: '新しい結果', ncode: 'n2', end: 1),
          ],
          hasNextPage: false,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      oldResponse.complete(
        const RankingPage(
          novels: <NovelInfo>[NovelInfo(title: '古い結果', ncode: 'n1')],
          hasNextPage: false,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final state = container.read(
        rankingProvider(NovelSource.kakuyomu, 'daily'),
      );
      expect(state.novels.single.title, '新しい結果');
      subscription.close();
    });

    test('AからBを経てAに戻った後も最初のAの応答は最新結果を上書きしない', () async {
      final responses = List<Completer<RankingPage>>.generate(
        3,
        (_) => Completer<RankingPage>(),
      );
      var fetchCount = 0;
      final site = _StubRankingSite(
        const <RankingPage>[],
        onFetch: (_) => responses[fetchCount++].future,
      );
      final container = ProviderContainer(
        overrides: [
          novelSiteRegistryProvider.overrideWithValue(
            <NovelSource, NovelSite>{NovelSource.kakuyomu: site},
          ),
          isOfflineModeProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);

      final subscription = container.listen(
        rankingProvider(NovelSource.kakuyomu, 'daily'),
        (_, _) {},
      );
      await Future<void>.delayed(Duration.zero);
      final setOngoing = container
          .read(
            rankingFilterStateProvider(NovelSource.kakuyomu, 'daily').notifier,
          )
          .setShowOnlyOngoing;
      setOngoing(value: true);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      setOngoing(value: false);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      responses[2].complete(
        const RankingPage(
          novels: <NovelInfo>[
            NovelInfo(title: '最新A', ncode: 'n3'),
          ],
          hasNextPage: false,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      responses[0].complete(
        const RankingPage(
          novels: <NovelInfo>[
            NovelInfo(title: '古いA', ncode: 'n1'),
          ],
          hasNextPage: false,
        ),
      );
      responses[1].complete(
        const RankingPage(
          novels: <NovelInfo>[
            NovelInfo(title: 'B', ncode: 'n2', end: 1),
          ],
          hasNextPage: false,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final state = container.read(
        rankingProvider(NovelSource.kakuyomu, 'daily'),
      );
      expect(state.novels.single.title, '最新A');
      subscription.close();
    });

    test('hasNextPage=false ならhasMoreがfalseになりそれ以上取得しない', () async {
      final site = _StubRankingSite(<RankingPage>[
        const RankingPage(
          novels: <NovelInfo>[
            NovelInfo(title: '作品A', ncode: 'n1'),
          ],
          hasNextPage: false,
        ),
      ]);
      final container = ProviderContainer(
        overrides: [
          novelSiteRegistryProvider.overrideWithValue(
            <NovelSource, NovelSite>{NovelSource.kakuyomu: site},
          ),
          isOfflineModeProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);

      final subscription = container.listen(
        rankingProvider(NovelSource.kakuyomu, 'daily'),
        (_, _) {},
      );
      // fetchNextPage の完了を待つ
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final state = container.read(
        rankingProvider(NovelSource.kakuyomu, 'daily'),
      );
      expect(state.novels, hasLength(1));
      expect(state.hasMore, isFalse);
      expect(site.callCount, 1);

      // hasMore=false なら追加の fetchNextPage はサイトを呼び出さない
      await container
          .read(rankingProvider(NovelSource.kakuyomu, 'daily').notifier)
          .fetchNextPage();
      await Future<void>.delayed(Duration.zero);
      expect(site.callCount, 1);
      subscription.close();
    });

    test('hasNextPage=true ならhasMoreがtrueのまま次のページを取得する', () async {
      final site = _StubRankingSite(<RankingPage>[
        const RankingPage(
          novels: <NovelInfo>[
            NovelInfo(title: '作品A', ncode: 'n1'),
          ],
          hasNextPage: true,
        ),
        const RankingPage(
          novels: <NovelInfo>[
            NovelInfo(title: '作品B', ncode: 'n2'),
          ],
          hasNextPage: false,
        ),
      ]);
      final container = ProviderContainer(
        overrides: [
          novelSiteRegistryProvider.overrideWithValue(
            <NovelSource, NovelSite>{NovelSource.kakuyomu: site},
          ),
          isOfflineModeProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);

      final subscription = container.listen(
        rankingProvider(NovelSource.kakuyomu, 'daily'),
        (_, _) {},
      );
      // 1ページ目取得
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(site.callCount, 1);

      // 次のページを取得
      await container
          .read(rankingProvider(NovelSource.kakuyomu, 'daily').notifier)
          .fetchNextPage();
      await Future<void>.delayed(Duration.zero);

      final state = container.read(
        rankingProvider(NovelSource.kakuyomu, 'daily'),
      );
      expect(state.novels, hasLength(2));
      expect(state.hasMore, isFalse);
      expect(site.callCount, 2);
      subscription.close();
    });
  });
}
