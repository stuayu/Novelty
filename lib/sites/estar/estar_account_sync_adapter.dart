import 'package:novelty/models/account_auth_state.dart';
import 'package:novelty/services/estar_auth_service.dart';
import 'package:novelty/sites/account_sync_adapter.dart';
import 'package:novelty/sites/novel_source.dart';

/// エブリスタのアカウント認証状態を共通UIへ公開するアダプター。
///
/// 同期エンドポイントは未確認のため、同期操作は実装しない。
class EstarAccountSyncAdapter implements AccountSyncAdapter {
  /// コンストラクタ。
  EstarAccountSyncAdapter({required EstarAuthService authService})
    : _authService = authService;

  final EstarAuthService _authService;

  @override
  NovelSource get source => NovelSource.estar;

  @override
  Future<AccountAuthState> getAuthState() async {
    if (!await _authService.isSessionValid()) {
      return AccountAuthState.loggedOut(source: source);
    }
    return AccountAuthState.loggedIn(source: source);
  }

  @override
  Future<bool> isLoggedIn() async => (await getAuthState()).isLoggedIn;

  @override
  Future<void> logout() => _authService.logout();

  @override
  Future<int> pullLibrary() {
    throw UnsupportedError('エブリスタのライブラリ同期は未対応です');
  }

  @override
  Future<AccountSyncOutcome> addToRemoteLibrary(String workId) {
    throw UnsupportedError('エブリスタのライブラリ追加は未対応です');
  }

  @override
  Future<AccountSyncOutcome> removeFromRemoteLibrary(String workId) {
    throw UnsupportedError('エブリスタのライブラリ削除は未対応です');
  }

  @override
  Future<bool> pushReadingProgress({
    required String workId,
    required int episode,
    String? position,
  }) {
    throw UnsupportedError('エブリスタの読書位置同期は未対応です');
  }
}
