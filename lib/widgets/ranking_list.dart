import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:novelty/providers/ranking_provider.dart';
import 'package:novelty/sites/novel_site.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:novelty/widgets/novel_list_tile.dart';

/// ランキングリストを表示するウィジェット。
class RankingList extends HookConsumerWidget {
  /// コンストラクタ。
  const RankingList({
    required this.source,
    required this.rankingType,
    super.key,
  });

  /// 提供サイト（プロバイダ）。
  final NovelSource source;

  /// ランキングの種類。
  final String rankingType;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // RankingNotifierから状態を取得
    final rankingState = ref.watch(rankingProvider(source, rankingType));

    // スクロール通知を監視するためのリスナー
    final scrollController = useScrollController();
    final hasListFooter =
        rankingState.isLoadingMore ||
        rankingState.error != null ||
        rankingState.hasMore;
    final showEmptyResult =
        rankingState.novels.isEmpty &&
        !rankingState.isLoading &&
        !hasListFooter;

    void loadNextPage() {
      unawaited(
        ref.read(rankingProvider(source, rankingType).notifier).fetchNextPage(),
      );
    }

    // 無限スクロールの検知
    // NotificationListenerを使用しても良いが、ScrollControllerで制御するほうが一般的
    // 下端に近づいたら次のページを読み込む
    useEffect(() {
      void onScroll() {
        if (!scrollController.hasClients) return;
        // 失敗後はスクロールでは再取得せず、フッターのボタン操作を待つ。
        if (ref.read(rankingProvider(source, rankingType)).error != null) {
          return;
        }
        final maxScroll = scrollController.position.maxScrollExtent;
        final currentScroll = scrollController.offset;

        // 画面の高さの0.8倍手前で読み込み開始
        if (currentScroll >= (maxScroll * 0.8)) {
          unawaited(
            ref
                .read(rankingProvider(source, rankingType).notifier)
                .fetchNextPage(),
          );
        }
      }

      scrollController.addListener(onScroll);
      return () => scrollController.removeListener(onScroll);
    }, [scrollController]);

    // 初回ロード失敗時のリトライボタン
    if (rankingState.error != null &&
        rankingState.novels.isEmpty &&
        rankingState.page == 1) {
      final errorMessage = rankingState.error is AccessRestrictedException
          ? 'アクセスが制限されています。しばらく待ってから再度お試しください'
          : '読み込みに失敗しました';
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(errorMessage, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () {
                unawaited(
                  ref
                      .read(rankingProvider(source, rankingType).notifier)
                      .refresh(),
                );
              },
              child: const Text('リトライ'),
            ),
          ],
        ),
      );
    }

    if (rankingState.isLoading && rankingState.novels.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(rankingProvider(source, rankingType).notifier).refresh();
      },
      child: ListView.builder(
        controller: scrollController,
        // アイテム数 + ローディングインジケータ（必要な場合）
        itemCount:
            rankingState.novels.length +
            (hasListFooter || showEmptyResult ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == rankingState.novels.length) {
            if (rankingState.isLoadingMore) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              );
            }

            if (rankingState.error != null) {
              final errorMessage =
                  rankingState.error is AccessRestrictedException
                  ? 'アクセスが制限されています。しばらく待ってから再度お試しください'
                  : '続きの読み込みに失敗しました';
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(errorMessage, textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: loadNextPage,
                      child: const Text('再試行'),
                    ),
                  ],
                ),
              );
            }

            if (rankingState.hasMore) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: TextButton(
                    onPressed: loadNextPage,
                    child: const Text('次のページを読み込む'),
                  ),
                ),
              );
            }

            if (rankingState.novels.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: Text('ランキング作品がありません')),
              );
            }
          }

          final novel = rankingState.novels[index];
          // 順位は現在のリストのインデックス + 1
          final rank = index + 1;

          return NovelListTile(
            item: novel,
            rank: rank,
            // enrichedData: ... ライブラリ状態が必要ならここで取得
          );
        },
      ),
    );
  }
}
