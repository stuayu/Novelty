import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:novelty/database/database.dart';
import 'package:novelty/domain/library_filter_state.dart';
import 'package:novelty/models/novel_info_extension.dart';
import 'package:novelty/models/novel_search_query.dart';
import 'package:novelty/repositories/novel_repository.dart';
import 'package:novelty/screens/search_page.dart';
import 'package:novelty/sites/novel_site.dart';
import 'package:novelty/sites/novel_site_registry.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:novelty/widgets/app_bar_source_dropdown.dart';
import 'package:novelty/widgets/library_filter_sheet.dart';
import 'package:novelty/widgets/library_sort_sheet.dart';
import 'package:novelty/widgets/novel_list_tile.dart';
import 'package:novelty/widgets/search_modal.dart';

/// [novel]のタイトルまたは作者名に[query]が含まれるかどうかを判定する。
///
/// 大文字小文字は区別しない。値が欠損している場合はヒットしない扱いとする。
bool _matchesSearchQuery(Novel novel, String query) {
  if (query.isEmpty) {
    return true;
  }
  final normalizedQuery = query.toLowerCase();
  final title = novel.title?.toLowerCase();
  final writer = novel.writer?.toLowerCase();
  return (title?.contains(normalizedQuery) ?? false) ||
      (writer?.contains(normalizedQuery) ?? false);
}

/// [entries]を[sortOrder]に従って並び替えた新しいリストを返す。
///
/// 更新日時・最終閲覧日時・タイトルはnullableなため、
/// 値が欠損している要素は末尾に寄せる。
List<LibraryNovelEntry> _sortEntries(
  List<LibraryNovelEntry> entries,
  LibrarySortOrder sortOrder,
) {
  final sorted = [...entries];

  int compareNullableString(String? a, String? b) {
    if (a == null && b == null) {
      return 0;
    }
    if (a == null) {
      return 1;
    }
    if (b == null) {
      return -1;
    }
    return a.compareTo(b);
  }

  int compareNullableInt(int? a, int? b) {
    if (a == null && b == null) {
      return 0;
    }
    if (a == null) {
      return 1;
    }
    if (b == null) {
      return -1;
    }
    return a.compareTo(b);
  }

  switch (sortOrder) {
    case LibrarySortOrder.addedAtDesc:
      sorted.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    case LibrarySortOrder.addedAtAsc:
      sorted.sort((a, b) => a.addedAt.compareTo(b.addedAt));
    case LibrarySortOrder.updatedAtDesc:
      // 最新エピソード掲載日(general_lastup)基準で新しい順に並べる。
      sorted.sort(
        (a, b) => compareNullableInt(
          b.novel.generalLastup,
          a.novel.generalLastup,
        ),
      );
    case LibrarySortOrder.updatedAtAsc:
      sorted.sort(
        (a, b) => compareNullableInt(
          a.novel.generalLastup,
          b.novel.generalLastup,
        ),
      );
    case LibrarySortOrder.titleAsc:
      sorted.sort(
        (a, b) => compareNullableString(a.novel.title, b.novel.title),
      );
    case LibrarySortOrder.titleDesc:
      sorted.sort(
        (a, b) => compareNullableString(b.novel.title, a.novel.title),
      );
    case LibrarySortOrder.lastReadDesc:
      // アプリの閲覧履歴で最近読んだ順に並べる。未読は末尾。
      sorted.sort(
        (a, b) => compareNullableInt(b.lastViewedAt, a.lastViewedAt),
      );
    case LibrarySortOrder.lastReadAsc:
      sorted.sort(
        (a, b) => compareNullableInt(a.lastViewedAt, b.lastViewedAt),
      );
  }

  return sorted;
}

/// "ライブラリ"ページのウィジェット。
class LibraryPage extends HookConsumerWidget {
  /// コンストラクタ。
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ライブラリ画面を開いている間、最新話掲載日などのメタデータを
    // バックグラウンドで定期的に再取得する。
    ref.watch(libraryMetadataRefresherProvider);
    final libraryNovelsAsync = ref.watch(libraryNovelsProvider);
    final filter = ref.watch(libraryFilterStateProvider);
    final searchController = useTextEditingController(
      text: filter.searchQuery,
    );

    // フィルタ・検索・ソート処理
    final displayedEntriesAsync = libraryNovelsAsync.whenData((entries) {
      final filtered = entries.where((entry) {
        final novel = entry.novel;

        // サイト絞り込みフィルタ
        if (filter.source != null && novel.source != filter.source) {
          return false;
        }

        // 連載状況フィルタ
        switch (filter.serialStatus) {
          case LibrarySerialStatus.all:
            break;
          case LibrarySerialStatus.ongoing:
            // end: 1 = 連載中, 0 = 完結/短編
            if (novel.end != 1) {
              return false;
            }
          case LibrarySerialStatus.completed:
            if (novel.end == 1) {
              return false;
            }
        }

        // ジャンルフィルタ
        if (filter.selectedGenreId != null) {
          if (novel.genreId != filter.selectedGenreId) {
            return false;
          }
        }

        // タイトル・作者名の検索
        if (!_matchesSearchQuery(novel, filter.searchQuery)) {
          return false;
        }

        return true;
      }).toList();

      return _sortEntries(filtered, filter.sortOrder);
    });

    void showSortSheet() {
      unawaited(
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (context) => LibrarySortSheet(
            currentOrder: filter.sortOrder,
            onOrderSelected: (order) {
              ref.read(libraryFilterStateProvider.notifier).setSortOrder(order);
              Navigator.pop(context);
            },
          ),
        ),
      );
    }

    void showFilterSheet() {
      // ジャンル一覧は選択中のサイトのマスタデータを使用する
      final genres = filter.source == null
          ? const <GenreMaster>[]
          : defaultNovelSiteRegistry[filter.source]!.genres;
      unawaited(
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (context) => LibraryFilterSheet(
            genres: genres,
            genreFilteringEnabled: filter.source != null,
            initialSerialStatus: filter.serialStatus,
            initialSelectedGenreId: filter.selectedGenreId,
            onApply: ({required serialStatus, required selectedGenreId}) {
              ref
                  .read(libraryFilterStateProvider.notifier)
                  .setSerialStatus(serialStatus);
              ref
                  .read(libraryFilterStateProvider.notifier)
                  .setSelectedGenreId(selectedGenreId);
            },
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('ライブラリ'),
            // プロバイダ絞り込み（探索画面と同一のAppBarドロップダウン）
            // タイトルの残り領域で中央に配置する
            Expanded(
              child: Center(
                child: AppBarSourceDropdown(
                  sources: NovelSource.values,
                  selected: filter.source,
                  allLabel: 'すべて',
                  onChanged: (source) {
                    ref
                        .read(libraryFilterStateProvider.notifier)
                        .setSource(source);
                  },
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              unawaited(
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  builder: (context) => SearchModal(
                    initialQuery: const NovelSearchQuery(),
                    onSearch: (query) {
                      Navigator.pop(context);
                      unawaited(
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (context) =>
                                SearchPage(initialQuery: query),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.sort),
            onPressed: showSortSheet,
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: showFilterSheet,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'タイトル・作者名で検索',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: filter.searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          searchController.clear();
                          ref
                              .read(libraryFilterStateProvider.notifier)
                              .setSearchQuery('');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              controller: searchController,
              onChanged: (value) => ref
                  .read(libraryFilterStateProvider.notifier)
                  .setSearchQuery(value),
            ),
          ),
          Expanded(
            child: displayedEntriesAsync.when(
              data: (entries) {
                if (entries.isEmpty) {
                  if (libraryNovelsAsync.asData?.value.isNotEmpty ?? false) {
                    return const Center(child: Text('条件に一致する小説がありません'));
                  }
                  return const Center(child: Text('ライブラリに小説がありません'));
                }
                return ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final novel = entries[index].novel;

                    // NovelListTileを使用するため、NovelInfoに変換
                    final novelData = novel.toModel();

                    return NovelListTile(
                      item: novelData,
                      onLongPress: () {
                        unawaited(
                          showDialog<void>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('削除の確認'),
                              content: Text(
                                '"${novel.title}"をライブラリから削除しますか？',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('キャンセル'),
                                ),
                                TextButton(
                                  onPressed: () async {
                                    await ref
                                        .read(novelRepositoryProvider)
                                        .removeFromLibrary(
                                          novel.source,
                                          novel.workId,
                                        );
                                    if (context.mounted) {
                                      Navigator.pop(context);
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text('ライブラリから削除しました'),
                                        ),
                                      );
                                    }
                                  },
                                  child: const Text('削除'),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(child: Text('Error: $err')),
            ),
          ),
        ],
      ),
    );
  }
}
