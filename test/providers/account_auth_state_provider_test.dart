import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/models/account_auth_state.dart';
import 'package:novelty/providers/auth_provider.dart';
import 'package:novelty/sites/account_sync_adapter.dart';
import 'package:novelty/sites/account_sync_registry.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:riverpod/riverpod.dart';

class _FakeAccountSyncAdapter implements AccountSyncAdapter {
  _FakeAccountSyncAdapter(this.state);

  final AccountAuthState state;

  @override
  NovelSource get source => state.source;

  @override
  Future<AccountAuthState> getAuthState() async => state;

  @override
  Future<bool> isLoggedIn() async => state.isLoggedIn;

  @override
  Future<void> logout() async {}

  @override
  Future<int> pullLibrary() async => 0;

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
  test('指定したサイトの共通認証状態を返す', () async {
    final container = ProviderContainer(
      overrides: [
        accountSyncRegistryProvider.overrideWithValue({
          NovelSource.narou: _FakeAccountSyncAdapter(
            const AccountAuthState.loggedIn(
              source: NovelSource.narou,
              accountId: 'narou-id',
              displayName: 'なろうユーザー',
            ),
          ),
          NovelSource.kakuyomu: _FakeAccountSyncAdapter(
            const AccountAuthState.loggedIn(
              source: NovelSource.kakuyomu,
            ),
          ),
        }),
      ],
    );
    addTearDown(container.dispose);

    final narou = await container.read(
      accountAuthStateProvider(NovelSource.narou).future,
    );
    final kakuyomu = await container.read(
      accountAuthStateProvider(NovelSource.kakuyomu).future,
    );

    expect(narou.displayName, 'なろうユーザー');
    expect(kakuyomu.isLoggedIn, isTrue);
    expect(kakuyomu.displayName, isNull);
  });

  test('未対応サイトはregistryがnullのままローカル処理可能な未ログイン状態を返す', () async {
    final registry = <NovelSource, AccountSyncAdapter>{};
    final container = ProviderContainer(
      overrides: [accountSyncRegistryProvider.overrideWithValue(registry)],
    );
    addTearDown(container.dispose);

    expect(registry[NovelSource.alphapolis], isNull);

    final state = await container.read(
      accountAuthStateProvider(NovelSource.alphapolis).future,
    );
    expect(state.source, NovelSource.alphapolis);
    expect(state.isLoggedIn, isFalse);
  });
}
