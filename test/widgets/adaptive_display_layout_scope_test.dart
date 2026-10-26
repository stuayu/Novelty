import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/utils/adaptive_display_layout.dart';
import 'package:novelty/widgets/adaptive_display_layout_scope.dart';

void main() {
  testWidgets('ネイティブ予約領域をMediaQueryと子画面へ伝える', (tester) async {
    const metrics = DisplayLayoutMetrics(
      widthClass: DisplayWidthClass.regular,
      divisionRegions: [Rect.fromLTWH(390, 0, 20, 800)],
      occlusionRegions: [Rect.fromLTWH(360, 8, 48, 32)],
    );
    BuildContext? childContext;

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => AdaptiveDisplayLayoutScope(
          layoutOverride: metrics,
          child: Builder(
            builder: (context) {
              childContext = context;
              return child!;
            },
          ),
        ),
        home: const Scaffold(body: Text('表示')),
      ),
    );

    expect(
      AdaptiveDisplayLayoutScope.maybeOf(childContext!),
      same(metrics),
    );
    expect(
      MediaQuery.of(childContext!).displayFeatures,
      containsAll([
        const ui.DisplayFeature(
          bounds: Rect.fromLTWH(390, 0, 20, 800),
          type: ui.DisplayFeatureType.hinge,
          state: ui.DisplayFeatureState.postureHalfOpened,
        ),
        const ui.DisplayFeature(
          bounds: Rect.fromLTWH(360, 8, 48, 32),
          type: ui.DisplayFeatureType.cutout,
          state: ui.DisplayFeatureState.unknown,
        ),
      ]),
    );
  });
}
