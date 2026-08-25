import 'package:novelty/models/account_auth_state.dart';
import 'package:novelty/repositories/form_auth_session_repository.dart';
import 'package:novelty/sites/account_sync_adapter.dart';
import 'package:novelty/sites/novel_source.dart';

/// フォーム認証だけが確認済みのサイト向け共通Adapter。
class FormAccountSyncAdapter implements AccountSyncAdapter {
  /// コンストラクタ。
  FormAccountSyncAdapter({
    required this.source,
    required FormAuthSessionRepository sessionRepository,
    required Future<bool> Function() validateSession,
    required Future<void> Function() clearSession,
  }) : _sessionRepository = sessionRepository,
       _validateSession = validateSession,
       _clearSession = clearSession;

  @override
  final NovelSource source;

  final FormAuthSessionRepository _sessionRepository;
  final Future<bool> Function() _validateSession;
  final Future<void> Function() _clearSession;

  @override
  Future<AccountAuthState> getAuthState() async {
    if (!await _validateSession()) {
      return AccountAuthState.loggedOut(source: source);
    }
    final accountId = await _sessionRepository.getAccountId();
    return AccountAuthState.loggedIn(
      source: source,
      accountId: accountId,
      displayName: accountId,
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
