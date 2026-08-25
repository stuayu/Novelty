import 'package:novelty/models/account_auth_state.dart';
import 'package:novelty/sites/novel_source.dart';

/// 外部サイトとのアカウント同期結果。
enum AccountSyncOutcome {
  /// 同期に成功した。
  success,

  /// ログインしていないため同期対象外。
  notLoggedIn,

  /// ログイン済みだが同期に失敗した。
  failed,
}

/// 保存済みの認証セッションが失効した場合の共通例外。
class AccountSessionExpiredException implements Exception {
  /// コンストラクタ。
  const AccountSessionExpiredException();

  @override
  String toString() => 'AccountSessionExpiredException';
}

/// 小説提供サイトのアカウント同期を抽象化するインターフェース。
///
/// UI やサイト固有の認証情報を公開せず、ライブラリと読書進捗の
/// 共通操作だけを提供する。
abstract interface class AccountSyncAdapter {
  /// 対象サイト。
  NovelSource get source;

  /// サイト横断の認証状態を取得する。
  Future<AccountAuthState> getAuthState();

  /// ログイン済みか確認する。
  Future<bool> isLoggedIn();

  /// 保存済みの認証情報を破棄する。
  Future<void> logout();

  /// リモートのライブラリをローカルへ取り込む。
  ///
  /// 同期した作品数を返す。
  Future<int> pullLibrary();

  /// 作品をリモートのライブラリへ追加する。
  Future<AccountSyncOutcome> addToRemoteLibrary(String workId);

  /// 作品をリモートのライブラリから削除する。
  Future<AccountSyncOutcome> removeFromRemoteLibrary(String workId);

  /// ローカルの読書位置をリモートへ反映する。
  ///
  /// [position] はサイト固有の詳細位置を確認できた場合だけ指定する。
  /// なろうのように話数だけで同期するサイトは無視してよい。
  Future<bool> pushReadingProgress({
    required String workId,
    required int episode,
    String? position,
  });
}
