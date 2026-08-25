import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:novelty/models/account_auth_state.dart';
import 'package:novelty/providers/auth_provider.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:novelty/widgets/accounts/kakuyomu_account_tile.dart';
import 'package:novelty/widgets/accounts/narou_account_tile.dart';

void main() {
  testWidgets('なろうタイルは共通認証状態の表示名を表示する', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountAuthStateProvider(NovelSource.narou).overrideWith(
            (ref) async => const AccountAuthState.loggedIn(
              source: NovelSource.narou,
              displayName: 'テストユーザー',
            ),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: NarouAccountTile())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('テストユーザー'), findsOneWidget);
    await tester.tap(find.text('テストユーザー'));
    await tester.pumpAndSettle();
    expect(find.text('ブックマークを同期'), findsOneWidget);
  });

  testWidgets('カクヨムタイルは共通認証状態でログイン済み表示を維持する', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountAuthStateProvider(NovelSource.kakuyomu).overrideWith(
            (ref) async => const AccountAuthState.loggedIn(
              source: NovelSource.kakuyomu,
            ),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: KakuyomuAccountTile())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ログイン済み'), findsOneWidget);
    await tester.tap(find.text('ログイン済み'));
    await tester.pumpAndSettle();
    expect(find.text('フォロー作品・閲覧履歴を同期'), findsOneWidget);
  });

  testWidgets('カクヨムのログイン操作はrouter経由で画面を開く', (tester) async {
    late GoRouter testRouter;
    testRouter = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(
            body: KakuyomuAccountTile(),
          ),
        ),
        GoRoute(
          path: '/more/kakuyomu-login',
          builder: (context, state) => const Scaffold(
            body: Text('カクヨムログインroute'),
          ),
        ),
      ],
    );
    addTearDown(testRouter.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountAuthStateProvider(NovelSource.kakuyomu).overrideWith(
            (ref) async => const AccountAuthState.loggedOut(
              source: NovelSource.kakuyomu,
            ),
          ),
        ],
        child: MaterialApp.router(routerConfig: testRouter),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('ログイン'));
    await tester.pumpAndSettle();

    expect(find.text('カクヨムログインroute'), findsOneWidget);
  });
}
