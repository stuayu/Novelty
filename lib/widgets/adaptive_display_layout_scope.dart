import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:novelty/utils/adaptive_display_layout.dart';

final Stream<DisplayLayoutMetrics> _nativeDisplayLayoutStream =
    const EventChannel('novelty/display_layout')
        .receiveBroadcastStream()
        .map(DisplayLayoutMetrics.fromPlatform)
        .where((metrics) => metrics != null)
        .cast<DisplayLayoutMetrics>()
        .asBroadcastStream();

/// iOSの予約領域をアプリ全体へ伝える。
class AdaptiveDisplayLayoutScope extends StatelessWidget {
  /// 画面レイアウトを通知するスコープを作成する。
  const AdaptiveDisplayLayoutScope({
    required this.child,
    this.layoutOverride,
    super.key,
  });

  /// レイアウト情報を適用する画面。
  final Widget child;

  /// テスト用に注入するレイアウト情報。
  @visibleForTesting
  final DisplayLayoutMetrics? layoutOverride;

  /// 最も近いスコープが保持するレイアウト情報を返す。
  static DisplayLayoutMetrics? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_InheritedDisplayLayout>()
      ?.metrics;

  @override
  Widget build(BuildContext context) {
    final shouldReadNativeLayout =
        layoutOverride == null &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.iOS;

    return StreamBuilder<DisplayLayoutMetrics>(
      stream: shouldReadNativeLayout ? _nativeDisplayLayoutStream : null,
      initialData: layoutOverride,
      builder: (context, snapshot) {
        final metrics = snapshot.data;
        final mediaQuery = MediaQuery.maybeOf(context);
        var scopedChild = child;
        if (metrics != null && mediaQuery != null) {
          scopedChild = MediaQuery(
            data: mediaQuery.copyWith(
              displayFeatures: _displayFeatures(mediaQuery, metrics),
            ),
            child: child,
          );
        }

        return _InheritedDisplayLayout(
          metrics: metrics,
          child: scopedChild,
        );
      },
    );
  }

  static List<ui.DisplayFeature> _displayFeatures(
    MediaQueryData mediaQuery,
    DisplayLayoutMetrics metrics,
  ) {
    final features = [...mediaQuery.displayFeatures];
    for (final bounds in metrics.divisionRegions) {
      if (features.any((feature) => feature.bounds == bounds)) {
        continue;
      }
      features.add(
        ui.DisplayFeature(
          bounds: bounds,
          type: ui.DisplayFeatureType.hinge,
          state: ui.DisplayFeatureState.postureHalfOpened,
        ),
      );
    }
    for (final bounds in metrics.occlusionRegions) {
      if (features.any((feature) => feature.bounds == bounds)) {
        continue;
      }
      features.add(
        ui.DisplayFeature(
          bounds: bounds,
          type: ui.DisplayFeatureType.cutout,
          state: ui.DisplayFeatureState.unknown,
        ),
      );
    }
    return features;
  }
}

class _InheritedDisplayLayout extends InheritedWidget {
  const _InheritedDisplayLayout({required this.metrics, required super.child});

  final DisplayLayoutMetrics? metrics;

  @override
  bool updateShouldNotify(_InheritedDisplayLayout oldWidget) =>
      metrics != oldWidget.metrics;
}
