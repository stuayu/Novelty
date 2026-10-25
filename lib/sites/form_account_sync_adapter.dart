import 'package:flutter/foundation.dart';
import 'package:novelty/models/account_auth_state.dart';
import 'package:novelty/repositories/form_auth_session_repository.dart';
import 'package:novelty/services/form_post_auth_service.dart';
import 'package:novelty/sites/account_sync_adapter.dart';
import 'package:novelty/sites/novel_source.dart';

/// フォーム認証だけが確認済みのサイト向け共通Adapter。
class FormAccountSyncAdapter implements AccountSyncAdapter {
  /// コンストラクタ。
  FormAccountSyncAdapter({
    required this.source,
    required FormAuthSessionRepository sessionRepository,
    required Future<void> Function() clearSession,
    Future<bool> Function(String cookieHeader)? validateSession,
    Future<FormAuthSessionValidity> Function(String cookieHeader)?
    validateSessionStatus,
  }) : assert(
         validateSession != null || validateSessionStatus != null,
         'validateSession または validateSessionStatus が必要です',
       ),
       _sessionRepository = sessionRepository,
       _validateSession = validateSession,
       _validateSessionStatus = validateSessionStatus,
       _clearSession = clearSession;

  @override
  final NovelSource source;

  final FormAuthSessionRepository _sessionRepository;

  /// 保存済みセッション。サイト固有の同期処理から参照する。
  @protected
  FormAuthSessionRepository get sessionRepository => _sessionRepository;

  final Future<bool> Function(String cookieHeader)? _validateSession;
  final Future<FormAuthSessionValidity> Function(String cookieHeader)?
  _validateSessionStatus;
  final Future<void> Function() _clearSession;

  @override
  Future<AccountAuthState> getAuthState() async {
    for (var attempt = 0; attempt < 5; attempt++) {
      final snapshot = await _sessionRepository.getSessionSnapshot();
      if (snapshot == null) {
        if (await _sessionRepository.getSessionSnapshot() == null) {
          return AccountAuthState.loggedOut(source: source);
        }
        continue;
      }

      final validity = _validateSessionStatus != null
          ? await _validateSessionStatus(snapshot.cookieHeader)
          : await _validateSession!(snapshot.cookieHeader)
          ? FormAuthSessionValidity.valid
          : FormAuthSessionValidity.invalid;
      final current = await _sessionRepository.getSessionSnapshot();
      if (current == null ||
          current.generation != snapshot.generation ||
          current.cookieHeader != snapshot.cookieHeader ||
          current.accountId != snapshot.accountId) {
        continue;
      }

      if (validity == FormAuthSessionValidity.invalid) {
        final cleared = await _sessionRepository
            .clearAllIfSessionCookieHeaderAndGenerationMatches(
              snapshot.generation,
              snapshot.cookieHeader,
            );
        if (cleared) return AccountAuthState.loggedOut(source: source);
        continue;
      }
      if (validity == FormAuthSessionValidity.unavailable) {
        return AccountAuthState.unverified(
          source: source,
          accountId: snapshot.accountId,
          displayName: snapshot.accountId,
        );
      }
      return AccountAuthState.loggedIn(
        source: source,
        accountId: snapshot.accountId,
        displayName: snapshot.accountId,
      );
    }
    final latest = await _sessionRepository.getSessionSnapshot();
    if (latest == null) return AccountAuthState.loggedOut(source: source);
    return AccountAuthState.unverified(
      source: source,
      accountId: latest.accountId,
      displayName: latest.accountId,
    );
  }

  @override
  Future<bool> isLoggedIn() async => (await getAuthState()).isLoggedIn;

  @override
  Future<void> logout() => _clearSession();

  @override
  Future<int> pullLibrary() => Future<int>.error(
    UnsupportedError('${source.label}のライブラリ取得endpointは未確認です'),
  );

  @override
  Future<AccountSyncOutcome> addToRemoteLibrary(String workId) =>
      Future<AccountSyncOutcome>.error(
        UnsupportedError('${source.label}のライブラリ追加endpointは未確認です'),
      );

  @override
  Future<AccountSyncOutcome> removeFromRemoteLibrary(String workId) =>
      Future<AccountSyncOutcome>.error(
        UnsupportedError('${source.label}のライブラリ削除endpointは未確認です'),
      );

  @override
  Future<bool> pushReadingProgress({
    required String workId,
    required int episode,
    String? position,
  }) => Future<bool>.error(
    UnsupportedError('${source.label}の読書位置同期endpointは未確認です'),
  );
}
