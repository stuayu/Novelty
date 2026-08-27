import 'package:flutter/material.dart';
import 'package:novelty/sites/novel_source.dart';

/// サイトを横並びのボタンで切り替えるバー。
///
/// 画面幅を全ボタンで等分し、ラベルはその幅に収まるまで自動で縮小する。
/// 横スクロールにすると狭い端末で右端のサイトが隠れてしまうため、
/// iPhone SE級の幅でも常に全サイトが一度に見える形にしている。
class SourceIconBar extends StatelessWidget {
  /// コンストラクタ。
  const SourceIconBar({
    required this.sources,
    required this.selected,
    required this.onChanged,
    this.allLabel,
    super.key,
  });

  /// バーの高さ。
  static const double barHeight = 44;

  /// 表示するサイト一覧。
  final List<NovelSource> sources;

  /// 選択中のサイト。[allLabel] 指定時は `null` が「すべて」を表す。
  final NovelSource? selected;

  /// 選択変更時のコールバック。「すべて」選択時は `null` を渡す。
  final ValueChanged<NovelSource?> onChanged;

  /// 「すべて」ボタンのラベル。指定した場合のみ先頭に追加する。
  final String? allLabel;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: barHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          children: [
            if (allLabel case final label?)
              Expanded(
                child: _SourceChip(
                  label: label,
                  tooltip: 'すべてのサイト',
                  isSelected: selected == null,
                  onTap: () => onChanged(null),
                ),
              ),
            for (final source in sources)
              Expanded(
                child: _SourceChip(
                  label: source.shortLabel,
                  tooltip: source.label,
                  isSelected: selected == source,
                  onTap: () => onChanged(source),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SourceChip extends StatelessWidget {
  const _SourceChip({
    required this.label,
    required this.tooltip,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final String tooltip;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: isSelected ? colors.secondaryContainer : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            // 選択状態を色だけに頼らず、枠線と太字でも区別できるようにする。
            side: BorderSide(
              color: isSelected ? colors.secondary : colors.outlineVariant,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: InkWell(
            key: Key('source_chip_$label'),
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: FittedBox(
                  // 等分した幅に収まらないラベルは縮小して表示する。
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      color: isSelected
                          ? colors.onSecondaryContainer
                          : colors.onSurface,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
