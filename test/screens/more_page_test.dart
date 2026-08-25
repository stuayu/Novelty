import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/models/account_auth_state.dart';
import 'package:novelty/providers/auth_provider.dart';
import 'package:novelty/screens/more_page.dart';
import 'package:novelty/sites/account_sync_adapter.dart';
import 'package:novelty/sites/account_sync_registry.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:riverpod/misc.dart' show Override;
import 'package:shared_preferences/shared_preferences.dart';

/// path_providerのモック実装
class FakePathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async {
    return '/mock/documents';
  }
}

class _FakeAccountSyncAdapter implements AccountSyncAdapter {
  _FakeAccountSyncAdapter(this.source);

  @override
  final NovelSource source;

  @override
  Future<AccountAuthState> getAuthState() async =>
      AccountAuthState.loggedOut(source: source);

  @override
  Future<bool> isLoggedIn() async => false;

  @override
  Future<void> logout() async {}

  @override
  Future<int> pullLibrary() async => 0;

  @override
  Future<AccountSyncOutcome> addToRemoteLibrary(String workId) async =>
      AccountSyncOutcome.notLoggedIn;

  @override
  Future<AccountSyncOutcome> removeFromRemoteLibrary(String workId) async =>
      AccountSyncOutcome.notLoggedIn;

  @override
  Future<bool> pushReadingProgress({
    required String workId,
    required int episode,
    String? position,
  }) async => false;
}

final List<Override> _authOverrides = [
  accountAuthStateProvider(NovelSource.narou).overrideWith(
    (ref) async => const AccountAuthState.loggedOut(source: NovelSource.narou),
  ),
  accountAuthStateProvider(NovelSource.kakuyomu).overrideWith(
    (ref) async =>
        const AccountAuthState.loggedOut(source: NovelSource.kakuyomu),
  ),
  for (final source in [
    NovelSource.alphapolis,
    NovelSource.hameln,
    NovelSource.novelup,
  ])
    accountAuthStateProvider(source).overrideWith(
      (ref) async => AccountAuthState.loggedOut(source: source),
    ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PathProviderPlatform.instance = FakePathProviderPlatform();
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    // 他のテストへの状態漏れを防ぐため、モックSharedPreferencesをリセットする
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('オフラインモードスイッチが表示される', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: _authOverrides,
        child: const MaterialApp(
          home: MorePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('オフラインモード'), findsOneWidget);
    expect(find.text('通信を行わず、保存済みのコンテンツのみ利用します'), findsOneWidget);
  });

  testWidgets('アカウント同期アダプターが登録されたサイトだけを表示する', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._authOverrides,
          accountSyncRegistryProvider.overrideWithValue({
            NovelSource.narou: _FakeAccountSyncAdapter(NovelSource.narou),
          }),
        ],
        child: const MaterialApp(home: MorePage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(NovelSource.narou.label), findsOneWidget);
    expect(find.text(NovelSource.kakuyomu.label), findsNothing);
    expect(find.text(NovelSource.alphapolis.label), findsNothing);
  });

  testWidgets('共通タイルに既存2サイトとフォーム認証3サイトが並ぶ', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._authOverrides,
          accountSyncRegistryProvider.overrideWithValue({
            for (final source in NovelSource.values)
              source: _FakeAccountSyncAdapter(source),
          }),
        ],
        child: const MaterialApp(home: MorePage()),
      ),
    );
    await tester.pumpAndSettle();

    for (final source in [
      NovelSource.narou,
      NovelSource.kakuyomu,
      NovelSource.alphapolis,
      NovelSource.hameln,
      NovelSource.novelup,
    ]) {
      expect(find.text(source.label), findsOneWidget);
    }
    expect(find.text(NovelSource.estar.label), findsNothing);
  });

  testWidgets('オフラインモードスイッチを切り替えると設定が永続化される', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: _authOverrides,
        child: const MaterialApp(
          home: MorePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // オフラインモードのSwitchListTileを明示的に指定
    final switchListTile = find.widgetWithText(SwitchListTile, 'オフラインモード');
    expect(switchListTile, findsOneWidget);

    await tester.tap(switchListTile);
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('is_offline_mode'), isTrue);
  });
}
