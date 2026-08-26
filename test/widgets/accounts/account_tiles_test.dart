import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:novelty/models/account_auth_state.dart';
import 'package:novelty/providers/auth_provider.dart';
import 'package:novelty/sites/account_sync_adapter.dart';
import 'package:novelty/sites/account_sync_registry.dart';
import 'package:novelty/sites/kakuyomu/kakuyomu_session_exception.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:novelty/widgets/accounts/account_tile.dart';
import 'package:novelty/widgets/accounts/kakuyomu_account_tile.dart';
import 'package:novelty/widgets/accounts/narou_account_tile.dart';

class _FakeAccountSyncAdapter implements AccountSyncAdapter {
  _FakeAccountSyncAdapter({required this.source, this.syncError});

  @override
  final NovelSource source;

  final Exception? syncError;
  bool loggedIn = true;
  int logoutCount = 0;

  @override
  Future<AccountAuthState> getAuthState() async => loggedIn
      ? AccountAuthState.loggedIn(source: source)
      : AccountAuthState.loggedOut(source: source);

  @override
  Future<bool> isLoggedIn() async => loggedIn;

  @override
  Future<void> logout() async {
    logoutCount++;
    loggedIn = false;
  }

  @override
  Future<int> pullLibrary() async {
    if (syncError case final error?) throw error;
    return 1;
  }

  @override
  Future<AccountSyncOutcome> addToRemoteLibrary(String workId) async =>
      AccountSyncOutcome.success;

  @override
  Future<AccountSyncOutcome> removeFromRemoteLibrary(String workId) async =>
      AccountSyncOutcome.success;

  @override
  Future<bool> pushReadingProgress({
    required String workId,
    required int episode,
    String? position,
  }) async => true;
}

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

  testWidgets('エブリスタタイルは表示されるが同期操作を出さない', (tester) async {
    final adapter = _FakeAccountSyncAdapter(source: NovelSource.estar);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountSyncRegistryProvider.overrideWithValue({
            NovelSource.estar: adapter,
          }),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: AccountTile(
              configuration: accountTileConfigurationFor(
                NovelSource.estar,
              )!,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('エブリスタ'), findsOneWidget);
    await tester.tap(find.text('ログイン済み'));
    await tester.pumpAndSettle();

    expect(find.text('ログアウト'), findsOneWidget);
    expect(find.byIcon(Icons.sync), findsNothing);
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

  testWidgets('共通アカウントタイルからログアウトできる', (tester) async {
    final adapter = _FakeAccountSyncAdapter(source: NovelSource.narou);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountSyncRegistryProvider.overrideWithValue({
            NovelSource.narou: adapter,
          }),
        ],
        child: const MaterialApp(home: Scaffold(body: NarouAccountTile())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('ログイン済み'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ログアウト'));
    await tester.pumpAndSettle();

    expect(adapter.logoutCount, 1);
    expect(find.text('ログイン'), findsOneWidget);
  });

  testWidgets('共通のセッション失効処理はログアウトして再ログインを促す', (tester) async {
    final adapter = _FakeAccountSyncAdapter(
      source: NovelSource.kakuyomu,
      syncError: const KakuyomuSessionExpiredException(),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountSyncRegistryProvider.overrideWithValue({
            NovelSource.kakuyomu: adapter,
          }),
        ],
        child: const MaterialApp(home: Scaffold(body: KakuyomuAccountTile())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('ログイン済み'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('フォロー作品・閲覧履歴を同期'));
    await tester.pumpAndSettle();

    expect(adapter.logoutCount, 1);
    expect(find.text('カクヨムのログイン期限が切れました。再ログインしてください'), findsOneWidget);
    expect(find.text('ログイン'), findsOneWidget);
  });
}
