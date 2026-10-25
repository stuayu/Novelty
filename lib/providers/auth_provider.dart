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
    bool rememberSession = true,
  }) async {
    state = const AsyncValue.loading();
    final authService = ref.read(narouAuthServiceProvider);
    try {
      final result = await authService.login(
        narouid: narouid,
        password: password,
        rememberSession: rememberSession,
      );

      if (result.isSuccess) {
        await _afterLogin(authService, result);
      }
      return result;
    } on Object catch (error, stackTrace) {
      authService.recordDiagnosticTrace(
        authService.createDiagnosticOperationId(),
        'login.provider.error',
        <String, Object?>{
          'stage': 'credential-login',
          'error': error.toString(),
          'stackTrace': stackTrace.toString(),
        },
      );
      return const NarouLoginResult.failure('ログイン処理に失敗しました');
    } finally {
      // 例外の有無にかかわらずローディングを解除する。
      state = const AsyncValue.data(null);
    }
  }

  /// MFAコードを確認し、成功時にセッション同期を開始する。
  Future<NarouLoginResult> verifyMfaCode(String code) async {
    state = const AsyncValue.loading();
    final authService = ref.read(narouAuthServiceProvider);
    try {
      final result = await authService.verifyMfaCode(code);
      if (result.isSuccess) await _afterLogin(authService, result);
      return result;
    } on Object catch (error, stackTrace) {
      authService.recordDiagnosticTrace(
        authService.createDiagnosticOperationId(),
        'login.provider.error',
        <String, Object?>{
          'stage': 'mfa-verification',
          'error': error.toString(),
          'stackTrace': stackTrace.toString(),
        },
      );
      return const NarouLoginResult.failure('認証コードの確認に失敗しました');
    } finally {
      state = const AsyncValue.data(null);
    }
  }

  /// MFA画面を閉じるときに保留中の認証チャレンジを破棄する。
  void cancelMfaChallenge() {
    ref.read(narouAuthServiceProvider).cancelMfaChallenge();
  }

  Future<void> _afterLogin(
    NarouAuthService authService,
    NarouLoginResult result,
  ) async {
    final adapter = ref.read(narouAccountSyncAdapterProvider);
    final operationId =
        result.diagnosticsOperationId ??
        authService.createDiagnosticOperationId();
    final stopwatch = Stopwatch()..start();
    authService.recordDiagnosticEvent(
      operationId,
      'post-login-sync.started',
      <String, Object?>{'source': adapter.source.name},
    );
    try {
      await adapter.pullLibrary();
    } on Object catch (error, stackTrace) {
      stopwatch.stop();
      authService
        ..recordDiagnosticEvent(
          operationId,
          'post-login-sync.failed',
          <String, Object?>{
            'source': adapter.source.name,
            'durationMs': stopwatch.elapsedMilliseconds,
            'errorType': error.runtimeType.toString(),
          },
        )
        ..recordDiagnosticTrace(
          operationId,
          'post-login-sync.error',
          <String, Object?>{
            'source': adapter.source.name,
            'error': error.toString(),
            'stackTrace': stackTrace.toString(),
          },
        );
      debugPrint(
        '[Novelty][Auth] ログイン後の同期失敗 type=${error.runtimeType}',
      );
    }
    if (stopwatch.isRunning) {
      stopwatch.stop();
      authService.recordDiagnosticEvent(
        operationId,
        'post-login-sync.completed',
        <String, Object?>{
          'source': adapter.source.name,
          'durationMs': stopwatch.elapsedMilliseconds,
        },
      );
    }
    ref.invalidate(accountAuthStateProvider(adapter.source));
  }
}
