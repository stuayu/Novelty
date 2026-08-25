import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:novelty/models/account_auth_state.dart';
import 'package:novelty/services/narou_auth_service.dart';
import 'package:novelty/sites/account_sync_registry.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:riverpod/misc.dart' show FutureProviderFamily;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'auth_provider.g.dart';

/// サイトを指定して共通認証状態を取得するプロバイダー。
final FutureProviderFamily<AccountAuthState, NovelSource>
accountAuthStateProvider = FutureProvider.family<AccountAuthState, NovelSource>(
  (ref, source) async {
    final adapter = ref.watch(accountSyncRegistryProvider)[source];
    if (adapter == null) {
      return AccountAuthState.loggedOut(source: source);
    }
    return adapter.getAuthState();
  },
);

@riverpod
/// なろうのログイン処理を管理するコントローラー。
class NarouLogin extends _$NarouLogin {
  @override
  Future<void> build() async {}

  /// ログインしてセッションを確立する。
  Future<NarouLoginResult> login({
    required String narouid,
    required String password,
  }) async {
    state = const AsyncValue.loading();
    final authService = ref.read(narouAuthServiceProvider);
    final result = await authService.login(
      narouid: narouid,
      password: password,
    );

    if (result.isSuccess) {
      state = const AsyncValue.data(null);
      // ログイン成功後に、なろうのリモートライブラリを同期する。
      final adapter = ref.read(narouAccountSyncAdapterProvider);
      await adapter.pullLibrary();
      ref.invalidate(accountAuthStateProvider(adapter.source));
    } else {
      state = const AsyncValue.data(null);
    }
    return result;
  }
}
