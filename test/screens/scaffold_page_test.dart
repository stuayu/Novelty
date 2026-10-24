import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:novelty/screens/scaffold_page.dart';

void main() {
  late GoRouter testRouter;

  setUp(() {
    testRouter = GoRouter(
      initialLocation: '/library',
      routes: [
        GoRoute(
          path: '/library',
          builder: (context, state) =>
              const ScaffoldPage(child: Text('ライブラリ内容')),
        ),
      ],
    );
  });

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
}
