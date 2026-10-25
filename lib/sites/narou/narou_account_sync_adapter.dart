import 'package:novelty/database/database.dart';
import 'package:novelty/models/account_auth_state.dart';
import 'package:novelty/repositories/auth_repository.dart';
import 'package:novelty/services/narou_auth_service.dart';
import 'package:novelty/services/narou_sync_service.dart';
import 'package:novelty/sites/account_sync_adapter.dart';
import 'package:novelty/sites/novel_source.dart';

/// なろうの既存同期サービスをサイト共通インターフェースへ変換するアダプター。
class NarouAccountSyncAdapter implements AccountSyncAdapter {
  /// コンストラクタ。
  NarouAccountSyncAdapter({
    required NarouSyncService syncService,
    required AppDatabase db,
    AuthRepository? authRepository,
    NarouAuthService? authService,
  }) : _syncService = syncService,
       _db = db,
       _authRepository = authRepository,
       _authService = authService;

  final NarouSyncService _syncService;
  final AppDatabase _db;
  final AuthRepository? _authRepository;
  final NarouAuthService? _authService;

  @override
  NovelSource get source => NovelSource.narou;

  AuthRepository get _repository =>
      _authRepository ?? _syncService.authRepository;

  NarouAuthService get _authenticationService =>
      _authService ?? NarouAuthService(authRepository: _repository);

  @override
  Future<AccountAuthState> getAuthState() async {
    final repository = _repository;
    for (var attempt = 0; attempt < 5; attempt++) {
      final snapshot = await repository.getSessionSnapshot();
      if (snapshot == null) return AccountAuthState.loggedOut(source: source);

      final validity = await _authenticationService.validateSession(
        snapshot.cookieHeader,
      );
      final current = await repository.getSessionSnapshot();
      if (current == null) return AccountAuthState.loggedOut(source: source);
      if (current.generation != snapshot.generation) continue;

      if (validity == NarouSessionValidity.invalid) {
        final cleared = await repository
            .clearAllIfSessionCookieHeaderAndGenerationMatches(
              snapshot.generation,
              snapshot.cookieHeader,
            );
        if (cleared) return AccountAuthState.loggedOut(source: source);
        // 同期応答でCookieが先に更新された場合は新しい値を検証する。
        continue;
      }

      return _accountStateForValidity(current, validity);
    }
    final latest = await repository.getSessionSnapshot();
    if (latest == null) return AccountAuthState.loggedOut(source: source);
    return AccountAuthState.unverified(
      source: source,
      accountId: latest.narouid,
      displayName: latest.username,
    );
  }

  AccountAuthState _accountStateForValidity(
    AuthSessionSnapshot snapshot,
    NarouSessionValidity validity,
  ) {
    if (validity == NarouSessionValidity.unavailable) {
      return AccountAuthState.unverified(
        source: source,
        accountId: snapshot.narouid,
        displayName: snapshot.username,
      );
    }
    return AccountAuthState.loggedIn(
      source: source,
      accountId: snapshot.narouid,
      displayName: snapshot.username,
    );
  }

  @override
  Future<bool> isLoggedIn() async => (await getAuthState()).isLoggedIn;

  @override
  Future<void> logout() => _authenticationService.logout();

  @override
  Future<int> pullLibrary() async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final synced = await _syncService.syncBookmarksFromNarou();
        return synced.length;
      } on NarouSessionExpiredException catch (error) {
        final cookieHeader = error.cookieHeader;
        final generation = error.generation;
        var cleared = false;
        if (cookieHeader != null) {
          cleared = generation != null
              ? await _repository
                    .clearAllIfSessionCookieHeaderAndGenerationMatches(
                      generation,
                      cookieHeader,
                    )
              : await _repository.clearAllIfSessionCookieHeaderMatches(
                  cookieHeader,
                );
        }
        if (cleared) {
          throw const AccountSessionExpiredException(
            clearSessionOnCatch: false,
          );
        }

        if (generation != null) {
          final current = await _repository.getSessionSnapshot();
          if (current == null) {
            throw const AccountSessionExpiredException(
              clearSessionOnCatch: false,
            );
          }
          if (attempt == 0 &&
              current.generation == generation &&
              cookieHeader != null &&
              current.cookieHeader != cookieHeader) {
            continue;
          }
        }

        throw const NarouBookmarkFetchException(
          '同期中に認証情報が更新されたため失効応答を破棄しました',
        );
      }
    }
    throw const NarouBookmarkFetchException('同期を完了できませんでした');
  }

  @override
  Future<AccountSyncOutcome> addToRemoteLibrary(String workId) async {
    final result = await _syncService.addBookmarkToNarou(workId);
    final outcome = _mapOutcome(result.outcome);

    if (outcome == AccountSyncOutcome.success) {
      await _db.markNarouBookmarkSynced(
        NovelSource.narou,
        workId,
        useridFavncode: result.useridFavncode,
        favToken: result.token,
      );
    }

    return outcome;
  }

  @override
  Future<AccountSyncOutcome> removeFromRemoteLibrary(String workId) async {
    final outcome = await _syncService.removeBookmarkFromNarou(workId);
    return _mapOutcome(outcome);
  }

  @override
  Future<bool> pushReadingProgress({
    required String workId,
    required int episode,
    String? position,
  }) {
    // なろうの既存しおりAPIは話数単位のため、サイト固有詳細位置は使用しない。
    return _syncService.setShioriIfLoggedIn(
      ncode: workId,
      episode: episode,
    );
  }

  AccountSyncOutcome _mapOutcome(NarouBookmarkSyncOutcome outcome) {
    return switch (outcome) {
      NarouBookmarkSyncOutcome.success => AccountSyncOutcome.success,
      NarouBookmarkSyncOutcome.notLoggedIn => AccountSyncOutcome.notLoggedIn,
      NarouBookmarkSyncOutcome.failed => AccountSyncOutcome.failed,
    };
  }
}
