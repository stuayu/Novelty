import 'package:novelty/database/database.dart';
import 'package:novelty/services/narou_sync_service.dart';
import 'package:novelty/sites/account_sync_adapter.dart';
import 'package:novelty/sites/novel_source.dart';

/// なろうの既存同期サービスをサイト共通インターフェースへ変換するアダプター。
class NarouAccountSyncAdapter implements AccountSyncAdapter {
  /// コンストラクタ。
  const NarouAccountSyncAdapter({
    required NarouSyncService syncService,
    required AppDatabase db,
  }) : _syncService = syncService,
       _db = db;

  final NarouSyncService _syncService;
  final AppDatabase _db;

  @override
  NovelSource get source => NovelSource.narou;

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
