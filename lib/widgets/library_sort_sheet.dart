import 'package:flutter/material.dart';
import 'package:novelty/domain/library_filter_state.dart';

/// ライブラリのソート順を選択するボトムシート。
class LibrarySortSheet extends StatelessWidget {
  /// コンストラクタ
  const LibrarySortSheet({
    required this.currentOrder,
    required this.onOrderSelected,
    super.key,
  });

  /// 現在選択されているソート順
  final LibrarySortOrder currentOrder;

  /// ソート順が選択された時のコールバック
  final ValueChanged<LibrarySortOrder> onOrderSelected;

  static const _labels = <LibrarySortOrder, String>{
    LibrarySortOrder.addedAtDesc: '追加日時が新しい順',
    LibrarySortOrder.addedAtAsc: '追加日時が古い順',
    LibrarySortOrder.updatedAtDesc: '更新日時が新しい順',
    LibrarySortOrder.updatedAtAsc: '更新日時が古い順',
    LibrarySortOrder.titleAsc: 'タイトル（あいうえお順）',
    LibrarySortOrder.titleDesc: 'タイトル（逆順）',
  };

  @override
  Widget build(BuildContext context) {
    final groups = [
      const _SortGroup(
        title: '追加日時',
        keys: [LibrarySortOrder.addedAtDesc, LibrarySortOrder.addedAtAsc],
      ),
      const _SortGroup(
        title: '更新日時',
        keys: [LibrarySortOrder.updatedAtDesc, LibrarySortOrder.updatedAtAsc],
      ),
      const _SortGroup(
        title: 'タイトル',
        keys: [LibrarySortOrder.titleAsc, LibrarySortOrder.titleDesc],
      ),
    ];

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return RadioGroup<LibrarySortOrder>(
          groupValue: currentOrder,
          onChanged: (value) {
            if (value != null) {
              onOrderSelected(value);
            }
          },
          child: Column(
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
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  '並び替え',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              // Content
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: groups.length,
                  itemBuilder: (context, index) {
                    final group = groups[index];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: Text(
                            group.title,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        ...group.keys.map((key) {
                          return RadioListTile<LibrarySortOrder>(
                            title: Text(_labels[key] ?? key.name),
                            value: key,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                            ),
                            dense: true,
                          );
                        }),
                        if (index < groups.length - 1) const Divider(height: 1),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SortGroup {
  const _SortGroup({required this.title, required this.keys});
  final String title;
  final List<LibrarySortOrder> keys;
}
