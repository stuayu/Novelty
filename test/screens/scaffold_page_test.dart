import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:novelty/screens/scaffold_page.dart';
import 'package:novelty/utils/adaptive_display_layout.dart';

void main() {
  late GoRouter testRouter;

  GoRouter createTestRouter({DisplayLayoutMetrics? displayLayout}) {
    return GoRouter(
      initialLocation: '/library',
      routes: [
        GoRoute(
          path: '/library',
          builder: (context, state) => ScaffoldPage(
            displayLayout: displayLayout,
            child: const SizedBox.expand(
              key: Key('content'),
              child: Text('ライブラリ内容'),
            ),
          ),
        ),
      ],
    );
  }

  setUp(() => testRouter = createTestRouter());

  tearDown(() => testRouter.dispose());

  testWidgets('狭い画面ではMaterial 3下部ナビゲーションを使う', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);

    await tester.pumpWidget(MaterialApp.router(routerConfig: testRouter));

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('広い画面では下部ナビゲーションをレールへ切り替える', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 800);

    await tester.pumpWidget(MaterialApp.router(routerConfig: testRouter));

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('右側にシステム予約領域があるcompact画面では右側にナビを置く', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);
    tester.view.padding = const FakeViewPadding(right: 48);
    testRouter.dispose();
    testRouter = createTestRouter(
      displayLayout: const DisplayLayoutMetrics(
        widthClass: DisplayWidthClass.compact,
      ),
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: testRouter));

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(tester.getCenter(find.byType(NavigationRail)).dx, greaterThan(200));
  });

  testWidgets('RTLでもナビレールをシステム予約領域の物理的な右側に置く', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);
    tester.view.padding = const FakeViewPadding(right: 48);
    testRouter.dispose();
    testRouter = createTestRouter(
      displayLayout: const DisplayLayoutMetrics(
        widthClass: DisplayWidthClass.compact,
      ),
    );

    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: testRouter,
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child!,
        ),
      ),
    );

    expect(
      tester
          .getCenter(find.byKey(const ValueKey('primary-navigation-rail')))
          .dx,
      greaterThan(tester.getCenter(find.byKey(const Key('content'))).dx),
    );
  });

  testWidgets('左右対称な広い画面ではRTLのleadingレールを右に置く', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 800);

    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: testRouter,
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child!,
        ),
      ),
    );

    expect(
      tester
          .getCenter(find.byKey(const ValueKey('primary-navigation-rail')))
          .dx,
      greaterThan(tester.getCenter(find.byKey(const Key('content'))).dx),
    );
  });

  testWidgets('縦の折り目をまたがない領域に画面を収める', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 800);
    testRouter.dispose();
    testRouter = createTestRouter(
      displayLayout: const DisplayLayoutMetrics(
        widthClass: DisplayWidthClass.regular,
        divisionRegions: [Rect.fromLTWH(390, 0, 20, 800)],
      ),
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: testRouter));

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(
      tester.getSize(find.byKey(const Key('content'))).width,
      inInclusiveRange(280, 390),
    );
    expect(
      tester
          .widget<NavigationRail>(
            find.byKey(const ValueKey('primary-navigation-rail')),
          )
          .extended,
      isFalse,
    );
  });

  testWidgets('ウィンドウの幅変更に追従してナビを再配置する', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);

    await tester.pumpWidget(MaterialApp.router(routerConfig: testRouter));
    expect(find.byType(NavigationBar), findsOneWidget);

    tester.view.physicalSize = const Size(1000, 800);
    await tester.pump();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });
}
