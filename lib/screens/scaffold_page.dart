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
    final selectedIndex = _calculateSelectedIndex(context);
    final isWide = MediaQuery.sizeOf(context).width >= 700;

    return Scaffold(
      body: isWide
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: selectedIndex,
                  labelType: NavigationRailLabelType.all,
                  onDestinationSelected: (index) =>
                      _onItemTapped(index, context),
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.book),
                      label: Text('ライブラリ'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.explore),
                      label: Text('見つける'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.history),
                      label: Text('履歴'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.more_horiz),
                      label: Text('もっと'),
                    ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: child),
              ],
            )
          : child,
      bottomNavigationBar: isWide
          ? null
          : BottomNavigationBar(
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.book),
                  label: 'ライブラリ',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.explore),
                  label: '見つける',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.history),
                  label: '履歴',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.more_horiz),
                  label: 'もっと',
                ),
              ],
              currentIndex: selectedIndex,
              selectedItemColor: Theme.of(context).colorScheme.primary,
              unselectedItemColor: Colors.grey,
              onTap: (idx) => _onItemTapped(idx, context),
              type: BottomNavigationBarType.fixed,
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
