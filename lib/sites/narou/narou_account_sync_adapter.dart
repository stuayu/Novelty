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
    if (!await repository.hasSessionCookies()) {
      return AccountAuthState.loggedOut(source: source);
    }

    if (!await _authenticationService.isSessionValid()) {
      await repository.clearAll();
      return AccountAuthState.loggedOut(source: source);
    }

    final accountId = await repository.getNarouid();
    final displayName = await repository.getUsername();
    if (accountId == null || displayName == null) {
      return AccountAuthState.loggedOut(source: source);
    }

    return AccountAuthState.loggedIn(
      source: source,
      accountId: accountId,
      displayName: displayName,
    );
  }

  @override
  Future<bool> isLoggedIn() async => (await getAuthState()).isLoggedIn;

  @override
  Future<void> logout() => _authenticationService.logout();

  @override
  Future<int> pullLibrary() async {
    final synced = await _syncService.syncBookmarksFromNarou();
    return synced.length;
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
