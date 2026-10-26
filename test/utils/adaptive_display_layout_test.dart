import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/utils/adaptive_display_layout.dart';

void main() {
  group('AdaptiveDisplayLayout.navigationPlacement', () {
    test('通常のiPhoneのcompact幅では下部ナビゲーションを使う', () {
      expect(
        AdaptiveDisplayLayout.navigationPlacement(
          widthClass: DisplayWidthClass.compact,
          safeAreaInsets: EdgeInsets.zero,
        ),
        NavigationPlacement.bottom,
      );
    });

    test('compact幅でも右側にシステム予約領域があれば右側レールを使う', () {
      expect(
        AdaptiveDisplayLayout.navigationPlacement(
          widthClass: DisplayWidthClass.compact,
          safeAreaInsets: const EdgeInsets.only(right: 48),
        ),
        NavigationPlacement.trailingRail,
      );
    });

    test('compact幅でも左側にシステム予約領域があれば左側レールを使う', () {
      expect(
        AdaptiveDisplayLayout.navigationPlacement(
          widthClass: DisplayWidthClass.compact,
          safeAreaInsets: const EdgeInsets.only(left: 48),
        ),
        NavigationPlacement.leadingRail,
      );
    });

    test('regular幅では左側レールを使う', () {
      expect(
        AdaptiveDisplayLayout.navigationPlacement(
          widthClass: DisplayWidthClass.regular,
          safeAreaInsets: EdgeInsets.zero,
        ),
        NavigationPlacement.leadingRail,
      );
    });

    test('幅クラスに関わらず折り目が有効ならレールへ切り替える', () {
      expect(
        AdaptiveDisplayLayout.navigationPlacement(
          widthClass: DisplayWidthClass.compact,
          safeAreaInsets: EdgeInsets.zero,
          hasActiveDivision: true,
        ),
        NavigationPlacement.leadingRail,
      );
    });
  });

  group('AdaptiveDisplayLayout.contentPaneBounds', () {
    test('折り目がなければ表示領域全体を返す', () {
      expect(
        AdaptiveDisplayLayout.contentPaneBounds(
          const Size(400, 800),
          const [],
        ),
        const Rect.fromLTWH(0, 0, 400, 800),
      );
    });

    test('縦の折り目をまたがない左側のペインを選ぶ', () {
      expect(
        AdaptiveDisplayLayout.contentPaneBounds(
          const Size(800, 800),
          const [Rect.fromLTWH(390, 0, 20, 800)],
        ),
        const Rect.fromLTWH(0, 0, 390, 800),
      );
    });

    test('横の折り目をまたがない下側のペインを選ぶ', () {
      expect(
        AdaptiveDisplayLayout.contentPaneBounds(
          const Size(800, 800),
          const [Rect.fromLTWH(0, 390, 800, 20)],
        ),
        const Rect.fromLTWH(0, 410, 800, 390),
      );
    });
  });

  group('AdaptiveDisplayLayout.readingColumnWidth', () {
    test('通常のiPhoneでは表示幅を変えない', () {
      expect(AdaptiveDisplayLayout.readingColumnWidth(390), 390);
    });

    test('広い画面では本文の読み幅を制限する', () {
      expect(AdaptiveDisplayLayout.readingColumnWidth(1200), 760);
    });
  });

  test('iOSのレイアウト情報をサイズクラスと折り目へ変換する', () {
    final metrics = DisplayLayoutMetrics.fromPlatform(<String, Object>{
      'horizontalSizeClass': 'regular',
      'divisionRegions': [
        <double>[390, 0, 20, 800],
      ],
    });

    expect(metrics?.widthClass, DisplayWidthClass.regular);
    expect(metrics?.divisionRegions, const [Rect.fromLTWH(390, 0, 20, 800)]);
  });

  test('iOSの予約カメラ領域もヒンジと分けて読み取る', () {
    final metrics = DisplayLayoutMetrics.fromPlatform(<String, Object>{
      'occlusionRegions': [
        <double>[320, 8, 48, 32],
      ],
    });

    expect(metrics?.divisionRegions, isEmpty);
    expect(metrics?.occlusionRegions, const [Rect.fromLTWH(320, 8, 48, 32)]);
  });
}
