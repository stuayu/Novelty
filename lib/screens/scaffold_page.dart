import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:novelty/router/router.dart';

/// Scaffoldのウィジェット。
class ScaffoldPage extends ConsumerWidget {
  /// コンストラクタ。
  const ScaffoldPage({required this.child, super.key});

  /// 子ウィジェット。
  /// Scaffoldのbodyとして表示されるウィジェット。
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const destinations = <NavigationDestination>[
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
    final width = MediaQuery.sizeOf(context).width;
    final useNavigationRail = width >= 600;
    final selectedIndex = _calculateSelectedIndex(context);

    return Scaffold(
      body: useNavigationRail
          ? Row(
              children: [
                NavigationRail(
                  extended: width >= 840,
                  selectedIndex: selectedIndex,
                  onDestinationSelected: (index) =>
                      _onItemTapped(index, context),
                  destinations: [
                    for (final destination in destinations)
                      NavigationRailDestination(
                        icon: destination.icon,
                        selectedIcon: destination.selectedIcon,
                        label: Text(destination.label),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: child),
              ],
            )
          : child,
      bottomNavigationBar: useNavigationRail
          ? null
          : NavigationBar(
              selectedIndex: selectedIndex,
              onDestinationSelected: (index) => _onItemTapped(index, context),
              destinations: destinations,
            ),
    );
  }

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

  void _onItemTapped(int index, BuildContext context) {
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
}
