import 'package:novelty/repositories/auth_repository.dart';
import 'package:novelty/services/narou_auth_service.dart';
import 'package:novelty/services/narou_sync_service.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'auth_provider.g.dart';

/// 認証ユーザー情報。
class NarouUser {
  /// コンストラクタ。
  const NarouUser({
    required this.narouid,
    required this.username,
  });

  /// ログインID。
  final String narouid;

  /// ユーザー名（表示名）。
  final String username;
}

@riverpod
/// なろうの認証状態を管理するプロバイダー。
///
/// `null` = 未ログイン、`NarouUser` = ログイン済み。
class Auth extends _$Auth {
  @override
  Future<NarouUser?> build() async {
    final repo = ref.watch(authRepositoryProvider);
    final hasSession = await repo.hasSessionCookies();
    if (!hasSession) return null;

    final authService = ref.read(narouAuthServiceProvider);
    final isValid = await authService.isSessionValid();
    if (!isValid) {
      await repo.clearAll();
      return null;
    }

    final narouid = await repo.getNarouid();
    final username = await repo.getUsername();
    if (narouid == null || username == null) return null;

    return NarouUser(narouid: narouid, username: username);
  }

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
      state = AsyncValue.data(
        NarouUser(
          narouid: narouid,
          username: result.username!,
        ),
      );
      // ログイン成功後にブックマークを同期する
      final syncService = ref.read(narouSyncServiceProvider);
      await syncService.syncBookmarksFromNarou();
    } else {
      state = const AsyncValue.data(null);
    }
    return result;
  }

  /// ログアウトしてセッションを破棄する。
  Future<void> logout() async {
    state = const AsyncValue.loading();
    final authService = ref.read(narouAuthServiceProvider);
    await authService.logout();
    state = const AsyncValue.data(null);
  }

  /// ブックマークを手動でなろうから同期する。
  Future<int> syncBookmarks() async {
    final syncService = ref.read(narouSyncServiceProvider);
    final synced = await syncService.syncBookmarksFromNarou();
    return synced.length;
  }
}
