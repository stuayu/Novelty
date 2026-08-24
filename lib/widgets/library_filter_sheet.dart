import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:novelty/domain/library_filter_state.dart';
import 'package:novelty/sites/novel_site.dart';

/// ライブラリのフィルタ（連載状況・ジャンル）を選択するボトムシート
///
/// ジャンル一覧はサイト実装のマスタデータ（[NovelSite.genres]）から受け取る。
class LibraryFilterSheet extends HookWidget {
  /// コンストラクタ
  const LibraryFilterSheet({
    required this.genres,
    required this.initialSerialStatus,
    required this.initialSelectedGenreId,
    required this.onApply,
    this.genreFilteringEnabled = true,
    super.key,
  });

  /// ジャンルのマスタデータ一覧（サイト実装が提供）。
  final List<GenreMaster> genres;

  /// ジャンル絞り込みを操作できるか
  final bool genreFilteringEnabled;

  /// 前回の「連載状況」設定
  final LibrarySerialStatus initialSerialStatus;

  /// 前回の「選択ジャンルID」設定（nullはすべて）
  final String? initialSelectedGenreId;

  /// 適用ボタン押下時のコールバック
  final void Function({
    required LibrarySerialStatus serialStatus,
    required String? selectedGenreId,
  })
  onApply;

  static const _serialStatusLabels = <LibrarySerialStatus, String>{
    LibrarySerialStatus.all: 'すべて',
    LibrarySerialStatus.ongoing: '連載中のみ',
    LibrarySerialStatus.completed: '完結済みのみ',
  };

  @override
  Widget build(BuildContext context) {
    // 状態管理
    final serialStatus = useState(initialSerialStatus);
    final selectedGenreId = useState(initialSelectedGenreId);

    // ジャンルデータの加工（カテゴリごとにグループ化）
    // useMemoizedで再計算を防ぐ
    final groupedGenres = useMemoized(() {
      final groups = <String, List<GenreMaster>>{};

      for (final genre in genres) {
        // "名称〔カテゴリ〕" の形式をパース（なろう形式）
        // カテゴリが無いジャンル（カクヨム等）はそのままの名前でグループ化
        final match = RegExp('(.+)〔(.+)〕').firstMatch(genre.name);
        final category = match?.group(2) ?? genre.name;
        groups.putIfAbsent(category, () => []).add(genre);
      }
      return groups;
    }, [genres]);

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () {
                      // リセット
                      serialStatus.value = LibrarySerialStatus.all;
                      selectedGenreId.value = null;
                    },
                    child: const Text('リセット'),
                  ),
                  Text(
                    '絞り込み',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  TextButton(
                    onPressed: () {
                      onApply(
                        serialStatus: serialStatus.value,
                        selectedGenreId: selectedGenreId.value,
                      );
                      Navigator.pop(context);
                    },
                    child: const Text('適用'),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // Content
            Expanded(
              child: RadioGroup<LibrarySerialStatus>(
                groupValue: serialStatus.value,
                onChanged: (value) {
                  if (value != null) {
                    serialStatus.value = value;
                  }
                },
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Status Section
                    Text(
                      '連載状況',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...LibrarySerialStatus.values.map((status) {
                      return RadioListTile<LibrarySerialStatus>(
                        title: Text(_serialStatusLabels[status]!),
                        value: status,
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      );
                    }),

                    const SizedBox(height: 24),

                    if (genreFilteringEnabled) ...[
                      // Genre Section
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'ジャンル',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          if (selectedGenreId.value != null)
                            TextButton.icon(
                              onPressed: () => selectedGenreId.value = null,
                              icon: const Icon(Icons.close, size: 16),
                              label: const Text('ジャンル解除'),
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ...groupedGenres.entries.map((entry) {
                        final category = entry.key;
                        final items = entry.value;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                category,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: items.map((genre) {
                                final isSelected =
                                    selectedGenreId.value == genre.id;

                                return FilterChip(
                                  label: Text(genre.name),
                                  selected: isSelected,
                                  onSelected: (selected) {
                                    selectedGenreId.value = selected
                                        ? genre.id
                                        : null;
                                  },
                                  showCheckmark: false,
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 12),
                          ],
                        );
                      }),
                    ] else
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text('サイトを選択するとジャンルを指定できます'),
                      ),
                    const SizedBox(height: 48), // Bottom padding
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
