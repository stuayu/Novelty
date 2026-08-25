import 'package:flutter/foundation.dart';
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
    try {
      final result = await authService.login(
        narouid: narouid,
        password: password,
      );

      if (result.isSuccess) {
        // ログイン成功後に、なろうのリモートライブラリを同期する。
        // 同期の失敗でログイン自体を失敗にはしない。
        final adapter = ref.read(narouAccountSyncAdapterProvider);
        try {
          await adapter.pullLibrary();
        } on Object catch (e) {
          debugPrint('[Novelty][Auth] ログイン後の同期に失敗: $e');
        }
        ref.invalidate(accountAuthStateProvider(adapter.source));
      }
      return result;
    } on Object catch (e) {
      return NarouLoginResult.failure('ログインに失敗しました: $e');
    } finally {
      // 例外の有無にかかわらずローディングを解除する。
      state = const AsyncValue.data(null);
    }
  }
}
