import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// 画面の横方向サイズクラス。
enum DisplayWidthClass {
  /// iPhoneのように横幅が狭い表示領域。
  compact,

  /// iPadやiPhone Duoの内側画面のように横幅が広い表示領域。
  regular,
}

/// アプリ内ナビゲーションを配置する辺。
enum NavigationPlacement {
  /// 画面下部。
  bottom,

  /// 画面左側。
  leadingRail,

  /// 画面右側。
  trailingRail,
}

/// iOSから届くサイズクラスとヒンジの状態。
@immutable
class DisplayLayoutMetrics {
  /// 表示領域のレイアウト情報を作成する。
  const DisplayLayoutMetrics({
    this.widthClass,
    this.divisionRegions = const [],
    this.occlusionRegions = const [],
  });

  /// UIKitが報告した横方向のサイズクラス。未指定ならFlutter側で推定する。
  final DisplayWidthClass? widthClass;

  /// 表示領域を分ける、現在有効なヒンジ領域。
  final List<Rect> divisionRegions;

  /// カメラやDynamic Islandなどの、操作要素を重ねない予約領域。
  final List<Rect> occlusionRegions;

  /// プラットフォームチャネルの値を安全に読み取る。
  static DisplayLayoutMetrics? fromPlatform(Object? value) {
    if (value is! Map) {
      return null;
    }

    final widthClass = switch (value['horizontalSizeClass']) {
      'compact' => DisplayWidthClass.compact,
      'regular' => DisplayWidthClass.regular,
      _ => null,
    };
    return DisplayLayoutMetrics(
      widthClass: widthClass,
      divisionRegions: _readRegions(value['divisionRegions']),
      occlusionRegions: _readRegions(value['occlusionRegions']),
    );
  }

  static List<Rect> _readRegions(Object? value) {
    if (value is! List) {
      return const [];
    }

    final regions = <Rect>[];
    for (final rawRegion in value) {
      if (rawRegion is! List || rawRegion.length != 4) {
        continue;
      }
      final values = rawRegion.whereType<num>().toList();
      if (values.length != 4 || values.any((number) => !number.isFinite)) {
        continue;
      }
      final rect = Rect.fromLTWH(
        values[0].toDouble(),
        values[1].toDouble(),
        values[2].toDouble(),
        values[3].toDouble(),
      );
      if (!rect.isEmpty) {
        regions.add(rect);
      }
    }

    return List.unmodifiable(regions);
  }
}

/// iPhone Duoなどの可変領域に合わせるレイアウト計算。
abstract final class AdaptiveDisplayLayout {
  /// 横書き本文が広がりすぎないようにする最大幅。
  static const double maxReadingColumnWidth = 760;

  /// 拡張ナビレールを使える最小の表示幅。
  static const double extendedRailMinWidth = 840;

  /// サイズクラスとシステムの横方向の予約領域からナビ位置を決める。
  static NavigationPlacement navigationPlacement({
    required DisplayWidthClass widthClass,
    required EdgeInsets safeAreaInsets,
    bool hasActiveDivision = false,
  }) {
    if (safeAreaInsets.right > safeAreaInsets.left) {
      return NavigationPlacement.trailingRail;
    }
    if (safeAreaInsets.left > safeAreaInsets.right) {
      return NavigationPlacement.leadingRail;
    }

    if (hasActiveDivision || widthClass == DisplayWidthClass.regular) {
      return NavigationPlacement.leadingRail;
    }

    return NavigationPlacement.bottom;
  }

  /// 折り目をまたがない、最も広い表示ペインを返す。
  static Rect contentPaneBounds(Size viewport, List<Rect> divisions) {
    final fullBounds = Rect.fromLTWH(
      0,
      0,
      math.max(0, viewport.width),
      math.max(0, viewport.height),
    );
    var panes = <Rect>[fullBounds];

    for (final division in divisions) {
      final clippedDivision = division.intersect(fullBounds);
      if (clippedDivision.isEmpty) {
        continue;
      }

      final isVerticalDivision =
          clippedDivision.height >= clippedDivision.width;
      final nextPanes = <Rect>[];
      for (final pane in panes) {
        if (!pane.overlaps(clippedDivision)) {
          nextPanes.add(pane);
          continue;
        }

        if (isVerticalDivision) {
          final leftEdge = clippedDivision.left.clamp(pane.left, pane.right);
          final rightEdge = clippedDivision.right.clamp(pane.left, pane.right);
          final leftPane = Rect.fromLTRB(
            pane.left,
            pane.top,
            leftEdge,
            pane.bottom,
          );
          final rightPane = Rect.fromLTRB(
            rightEdge,
            pane.top,
            pane.right,
            pane.bottom,
          );
          if (!leftPane.isEmpty) {
            nextPanes.add(leftPane);
          }
          if (!rightPane.isEmpty) {
            nextPanes.add(rightPane);
          }
        } else {
          final topEdge = clippedDivision.top.clamp(pane.top, pane.bottom);
          final bottomEdge = clippedDivision.bottom.clamp(
            pane.top,
            pane.bottom,
          );
          final bottomPane = Rect.fromLTRB(
            pane.left,
            bottomEdge,
            pane.right,
            pane.bottom,
          );
          final topPane = Rect.fromLTRB(
            pane.left,
            pane.top,
            pane.right,
            topEdge,
          );
          if (!bottomPane.isEmpty) {
            nextPanes.add(bottomPane);
          }
          if (!topPane.isEmpty) {
            nextPanes.add(topPane);
          }
        }
      }

      if (nextPanes.isNotEmpty) {
        panes = nextPanes;
      }
    }

    panes.sort((a, b) => (b.width * b.height).compareTo(a.width * a.height));
    return panes.first;
  }

  /// 利用できる幅に合わせて、読書列の最大幅を返す。
  static double readingColumnWidth(double availableWidth) =>
      availableWidth.clamp(0, maxReadingColumnWidth).toDouble();
}
