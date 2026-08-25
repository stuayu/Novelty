import 'package:novelty/sites/novel_source.dart';

/// サイト横断のアカウント認証状態。
class AccountAuthState {
  /// ログイン済み状態。
  const AccountAuthState.loggedIn({
    required this.source,
    this.accountId,
    this.displayName,
  }) : isLoggedIn = true;

  /// 未ログイン状態。
  const AccountAuthState.loggedOut({required this.source})
    : isLoggedIn = false,
      accountId = null,
      displayName = null;

  /// 対象サイト。
  final NovelSource source;

  /// ログイン済みか。
  final bool isLoggedIn;

  /// サイト上のアカウント識別子。取得できないサイトでは `null`。
  final String? accountId;

  /// UIに表示できるアカウント名。取得できないサイトでは `null`。
  final String? displayName;
}
