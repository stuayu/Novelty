import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:novelty/screens/scaffold_page.dart';

void main() {
  testWidgets('広い画面ではNavigationRail、狭い画面では下部ナビを表示する', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const ScaffoldPage(
            child: Center(child: Text('content')),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(BottomNavigationBar), findsNothing);

    tester.view.physicalSize = const Size(400, 800);
    await tester.pump();
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(BottomNavigationBar), findsOneWidget);
  });
}
