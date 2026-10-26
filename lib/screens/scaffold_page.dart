import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:novelty/router/router.dart';
import 'package:novelty/utils/adaptive_display_layout.dart';
import 'package:novelty/widgets/adaptive_display_layout_scope.dart';

/// Scaffoldのウィジェット。
class ScaffoldPage extends ConsumerWidget {
  /// コンストラクタ。
  const ScaffoldPage({
    required this.child,
    this.displayLayout,
    super.key,
  });

  /// Scaffoldのbodyとして表示されるウィジェット。
  final Widget child;

  /// レイアウト情報。通常はiOSブリッジまたはFlutterの表示情報を使う。
  @visibleForTesting
  final DisplayLayoutMetrics? displayLayout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scopeMetrics = AdaptiveDisplayLayoutScope.maybeOf(context);
    final metrics = displayLayout ?? scopeMetrics;

    return LayoutBuilder(
      builder: (context, constraints) {
        final mediaQuery = MediaQuery.of(context);
        final viewport = Size(
          constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : mediaQuery.size.width,
          constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : mediaQuery.size.height,
        );
        final flutterDivisions = <Rect>[
          for (final feature in mediaQuery.displayFeatures)
            if (feature.type == ui.DisplayFeatureType.hinge ||
                feature.type == ui.DisplayFeatureType.fold)
              feature.bounds,
        ];
        final divisions = <Rect>{
          ...?metrics?.divisionRegions,
          ...flutterDivisions,
        }.toList();
        final widthClass =
            metrics?.widthClass ??
            (viewport.width >= 600
                ? DisplayWidthClass.regular
                : DisplayWidthClass.compact);
        final hasActiveDivision = divisions.isNotEmpty;
        final placement = AdaptiveDisplayLayout.navigationPlacement(
          widthClass: widthClass,
          safeAreaInsets: mediaQuery.padding,
          hasActiveDivision: hasActiveDivision,
        );
        final selectedIndex = _calculateSelectedIndex(context);
        final paneBounds = AdaptiveDisplayLayout.contentPaneBounds(
          viewport,
          divisions,
        );
        final railAvailableWidth = hasActiveDivision
            ? paneBounds.width
            : viewport.width;
        final useExtendedRail =
            widthClass == DisplayWidthClass.regular &&
            railAvailableWidth >= AdaptiveDisplayLayout.extendedRailMinWidth;
        final textDirection = Directionality.of(context);
        final hasAsymmetricHorizontalSafeArea =
            mediaQuery.padding.left != mediaQuery.padding.right;
        final railOnPhysicalLeft = switch (placement) {
          NavigationPlacement.bottom ||
          NavigationPlacement.trailingRail => false,
          NavigationPlacement.leadingRail =>
            hasActiveDivision || hasAsymmetricHorizontalSafeArea
                ? mediaQuery.padding.left > mediaQuery.padding.right
                : textDirection == TextDirection.ltr,
        };

        Widget buildRail() => NavigationRail(
          key: const ValueKey('primary-navigation-rail'),
          extended: useExtendedRail,
          selectedIndex: selectedIndex,
          onDestinationSelected: (index) => _onItemTapped(index, context),
          destinations: _destinations
              .map(
                (destination) => NavigationRailDestination(
                  icon: destination.icon,
                  selectedIcon: destination.selectedIcon,
                  label: Text(destination.label),
                ),
              )
              .toList(),
        );

        Widget placeRail({required bool onLeft}) {
          final rail = Directionality(
            textDirection: textDirection,
            child: SafeArea(
              top: false,
              left: onLeft,
              right: !onLeft,
              bottom: false,
              child: buildRail(),
            ),
          );
          final content = Directionality(
            textDirection: textDirection,
            child: child,
          );
          return Directionality(
            textDirection: TextDirection.ltr,
            child: Row(
              children: onLeft
                  ? [
                      rail,
                      const VerticalDivider(width: 1),
                      Expanded(child: content),
                    ]
                  : [
                      Expanded(child: content),
                      const VerticalDivider(width: 1),
                      rail,
                    ],
            ),
          );
        }

        final body = switch (placement) {
          NavigationPlacement.bottom => child,
          NavigationPlacement.leadingRail => placeRail(
            onLeft: railOnPhysicalLeft,
          ),
          NavigationPlacement.trailingRail => placeRail(onLeft: false),
        };

        final paneBody = hasActiveDivision
            ? Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fromRect(
                    rect: paneBounds,
                    child: MediaQuery(
                      data: _mediaQueryForPane(
                        mediaQuery,
                        paneBounds,
                        viewport,
                      ),
                      child: body,
                    ),
                  ),
                ],
              )
            : body;

        return Scaffold(
          body: paneBody,
          bottomNavigationBar: placement == NavigationPlacement.bottom
              ? NavigationBar(
                  selectedIndex: selectedIndex,
                  onDestinationSelected: (index) =>
                      _onItemTapped(index, context),
                  destinations: _destinations,
                )
              : null,
        );
      },
    );
  }

  static const _destinations = <NavigationDestination>[
    NavigationDestination(
      icon: Icon(Icons.book),
      label: 'ライブラリ',
      tooltip: 'ライブラリ',
    ),
    NavigationDestination(
      icon: Icon(Icons.explore),
      label: '見つける',
      tooltip: '見つける',
    ),
    NavigationDestination(
      icon: Icon(Icons.history),
      label: '履歴',
      tooltip: '履歴',
    ),
    NavigationDestination(
      icon: Icon(Icons.more_horiz),
      label: 'もっと',
      tooltip: 'もっと',
    ),
  ];

  static int _calculateSelectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    if (location.startsWith('/explore')) {
      return 1;
    }
    if (location.startsWith('/history')) {
      return 2;
    }
    if (location.startsWith('/more')) {
      return 3;
    }
    return 0;
  }

  static void _onItemTapped(int index, BuildContext context) {
    switch (index) {
      case 0:
        const LibraryRoute().go(context);
      case 1:
        const ExploreRoute().go(context);
      case 2:
        const HistoryRoute().go(context);
      case 3:
        const MoreRoute().go(context);
    }
  }

  static MediaQueryData _mediaQueryForPane(
    MediaQueryData mediaQuery,
    Rect pane,
    Size viewport,
  ) {
    EdgeInsets insetsForPane(EdgeInsets insets) => EdgeInsets.only(
      left: pane.left <= 0 ? insets.left : 0,
      top: pane.top <= 0 ? insets.top : 0,
      right: pane.right >= viewport.width ? insets.right : 0,
      bottom: pane.bottom >= viewport.height ? insets.bottom : 0,
    );

    return mediaQuery.copyWith(
      size: pane.size,
      padding: insetsForPane(mediaQuery.padding),
      viewPadding: insetsForPane(mediaQuery.viewPadding),
      systemGestureInsets: insetsForPane(mediaQuery.systemGestureInsets),
      displayFeatures: const [],
    );
  }
}
