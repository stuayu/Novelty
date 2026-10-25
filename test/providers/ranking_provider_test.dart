import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:novel_parser_core/novel_parser_core.dart';
import 'package:novelty/domain/ranking_filter_state.dart';
import 'package:novelty/models/novel_info.dart';
import 'package:novelty/models/novel_search_result.dart';
import 'package:novelty/models/ranking_page.dart';
import 'package:novelty/providers/ranking_provider.dart';
import 'package:novelty/services/api_service.dart';
import 'package:novelty/services/narou_auth_diagnostics.dart';
import 'package:novelty/sites/alphapolis/alphapolis_site.dart';
import 'package:novelty/sites/novel_site.dart';
import 'package:novelty/sites/novel_site_registry.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:novelty/utils/settings_provider.dart';
import 'package:novelty/utils/value_wrapper.dart';

import 'novel_info_offline_test.mocks.dart';

/// 固定の [RankingPage] を返すだけの最小のサイト実装。
///
/// ランキング以外のメソッドはテストで使用しない。
class _StubRankingSite extends NovelSite implements RankingCacheControl {
  _StubRankingSite(this._pages);

  /// ページ番号（1始まり）に対応する [RankingPage] の一覧。
  final List<RankingPage> _pages;

  /// fetchRanking が呼ばれた回数。
  int callCount = 0;

  /// refreshRanking が呼ばれた回数。
  int refreshCallCount = 0;

  @override
  NovelSource get source => NovelSource.kakuyomu;

  @override
  List<GenreMaster> get genres => const <GenreMaster>[];

  @override
  List<RankingTypeMaster> get rankingTypes => const <RankingTypeMaster>[];

  @override
  String? metaText(NovelInfo info) => null;

  @override
  List<NovelContentElement> parseEpisodeBody(String html) =>
      throw UnsupportedError('テスト対象外');

  @override
  Future<RankingPage> fetchRanking(
    String rankingType, {
    int page = 1,
  }) async {
    callCount++;
    final index = (page - 1).clamp(0, _pages.length - 1);
    return _pages[index];
  }

  @override
  Future<RankingPage> refreshRanking(
    String rankingType, {
    int page = 1,
  }) async {
    refreshCallCount++;
    final index = (page - 1).clamp(0, _pages.length - 1);
    return _pages[index];
  }
}

/// 各ランキング要求の完了タイミングを制御するテストサイト。
class _ControlledRankingSite extends _StubRankingSite {
  _ControlledRankingSite() : super(const <RankingPage>[]);

  final List<Completer<RankingPage>> pendingPages = <Completer<RankingPage>>[];

  @override
  Future<RankingPage> fetchRanking(
    String rankingType, {
    int page = 1,
  }) {
    callCount++;
    final completer = Completer<RankingPage>();
    pendingPages.add(completer);
    return completer.future;
  }
}

class _FailingAlphaPolisRankingSite extends _StubRankingSite {
  _FailingAlphaPolisRankingSite() : super(const <RankingPage>[]);

  @override
  NovelSource get source => NovelSource.alphapolis;

  @override
  Future<RankingPage> fetchRanking(
    String rankingType, {
    int page = 1,
  }) async => throw const AlphapolisHttpException(
    503,
    'https://www.alphapolis.co.jp/ranking?token=secret',
  );
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
    test('表示から300ミリ秒以内に離れたランキングは取得しない', () async {
      final mockApiService = MockApiService();
      when(
        mockApiService.searchNovels(any),
      ).thenAnswer(
        (_) async => const NovelSearchResult(novels: [], allCount: 0),
      );
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
      await Future<void>.delayed(const Duration(milliseconds: 100));
      subscription.close();
      await Future<void>.delayed(const Duration(milliseconds: 250));

      verifyNever(mockApiService.searchNovels(any));
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
      await Future<void>.delayed(const Duration(milliseconds: 350));

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

  group('RankingNotifier', () {
    test('アルファポリスランキングの例外をTraceログへ残す', () async {
      final consoleLines = <String>[];
      final diagnostics = NarouAuthDiagnosticsLogger(
        enabled: true,
        directoryResolver: () async =>
            throw StateError('test file output disabled'),
        consoleSink: consoleLines.add,
      );

      final site = _FailingAlphaPolisRankingSite();
      final container = ProviderContainer(
        overrides: [
          appDiagnosticsLoggerProvider.overrideWithValue(diagnostics),
          novelSiteRegistryProvider.overrideWithValue(
            <NovelSource, NovelSite>{NovelSource.alphapolis: site},
          ),
          isOfflineModeProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        rankingProvider(NovelSource.alphapolis, '24hpt'),
        (_, _) {},
      );
      addTearDown(subscription.close);

      await Future<void>.delayed(const Duration(milliseconds: 350));

      expect(
        container.read(rankingProvider(NovelSource.alphapolis, '24hpt')).error,
        isA<AlphapolisHttpException>(),
      );
      await diagnostics.flush();
      final logEntries = consoleLines
          .where((line) => line.startsWith('[NoveltyDiagnostics] {'))
          .map(
            (line) =>
                jsonDecode(line.substring(line.indexOf('{')))
                    as Map<String, dynamic>,
          )
          .toList();
      final failure = logEntries.singleWhere(
        (entry) => entry['event'] == 'ranking.fetch.failed.trace',
      );
      expect(failure['source'], 'alphapolis');
      expect(failure['rankingType'], '24hpt');
      expect(failure['errorType'], 'AlphapolisHttpException');
      expect(failure['httpStatusCode'], 503);
      expect(
        failure['requestRoute'],
        'www.alphapolis.co.jp/ranking',
      );
      expect(failure['requestRoute'], isNot(contains('secret')));
      expect(failure['stackTrace'], contains('fetchRanking'));
    });

    test('フィルター変更前の遅延レスポンスを新しいランキングへ混ぜない', () async {
      final site = _ControlledRankingSite();
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
      addTearDown(subscription.close);

      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(site.pendingPages, hasLength(1));

      container
          .read(
            rankingFilterStateProvider(
              NovelSource.kakuyomu,
              'daily',
            ).notifier,
          )
          .setSelectedGenreId('new');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(site.pendingPages, hasLength(2));

      site.pendingPages[0].complete(
        const RankingPage(
          novels: <NovelInfo>[
            NovelInfo(title: '古い条件', ncode: 'old', genreId: 'old'),
          ],
          hasNextPage: false,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(rankingProvider(NovelSource.kakuyomu, 'daily')).novels,
        isEmpty,
      );

      site.pendingPages[1].complete(
        const RankingPage(
          novels: <NovelInfo>[
            NovelInfo(title: '新しい条件', ncode: 'new', genreId: 'new'),
          ],
          hasNextPage: false,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final state = container.read(
        rankingProvider(NovelSource.kakuyomu, 'daily'),
      );
      expect(state.novels.map((novel) => novel.title), <String>['新しい条件']);
    });

    test('明示更新はサイトのランキングキャッシュを迂回する', () async {
      final site = _StubRankingSite(<RankingPage>[
        const RankingPage(
          novels: <NovelInfo>[NovelInfo(title: '作品A', ncode: 'n1')],
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
      addTearDown(subscription.close);
      await Future<void>.delayed(const Duration(milliseconds: 350));

      await container
          .read(rankingProvider(NovelSource.kakuyomu, 'daily').notifier)
          .refresh();

      expect(site.callCount, 1);
      expect(site.refreshCallCount, 1);
    });

    test('取得済みランキングはタブを離れて戻っても再取得しない', () async {
      final site = _StubRankingSite(<RankingPage>[
        const RankingPage(
          novels: <NovelInfo>[NovelInfo(title: '作品A', ncode: 'n1')],
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

      final firstSubscription = container.listen(
        rankingProvider(NovelSource.kakuyomu, 'daily'),
        (_, _) {},
      );
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(site.callCount, 1);
      firstSubscription.close();
      await Future<void>.delayed(Duration.zero);

      final secondSubscription = container.listen(
        rankingProvider(NovelSource.kakuyomu, 'daily'),
        (_, _) {},
      );
      await Future<void>.delayed(const Duration(milliseconds: 350));

      expect(site.callCount, 1);
      expect(
        container
            .read(rankingProvider(NovelSource.kakuyomu, 'daily'))
            .novels
            .single
            .title,
        '作品A',
      );
      secondSubscription.close();
    });

    test('取得済みランキングは10分経過後に破棄して次回表示で再取得する', () {
      fakeAsync((async) {
        void elapseAndFlush(Duration duration) {
          async
            ..elapse(duration)
            ..flushMicrotasks();
        }

        final site = _StubRankingSite(<RankingPage>[
          const RankingPage(
            novels: <NovelInfo>[NovelInfo(title: '作品A', ncode: 'n1')],
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

        final firstSubscription = container.listen(
          rankingProvider(NovelSource.kakuyomu, 'daily'),
          (_, _) {},
        );
        elapseAndFlush(const Duration(milliseconds: 300));
        expect(site.callCount, 1);
        firstSubscription.close();
        async.flushMicrotasks();

        elapseAndFlush(const Duration(minutes: 10));
        final secondSubscription = container.listen(
          rankingProvider(NovelSource.kakuyomu, 'daily'),
          (_, _) {},
        );
        elapseAndFlush(const Duration(milliseconds: 300));

        expect(site.callCount, 2);
        secondSubscription.close();
        container.dispose();
      });
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
      await Future<void>.delayed(const Duration(milliseconds: 350));

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
      await Future<void>.delayed(const Duration(milliseconds: 350));
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
