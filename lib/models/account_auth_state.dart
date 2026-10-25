import 'package:novelty/sites/novel_source.dart';

/// サイト横断のアカウント認証状態。
class AccountAuthState {
  /// ログイン済み状態。
  const AccountAuthState.loggedIn({
    required this.source,
    this.accountId,
    this.displayName,
  }) : hasSession = true,
       isLoggedIn = true,
       isVerified = true;

  /// 認証情報は保存済みだが、通信障害などで状態を確認できない。
  const AccountAuthState.unverified({
    required this.source,
    this.accountId,
    this.displayName,
  }) : hasSession = true,
       isLoggedIn = false,
       isVerified = false;

  /// 未ログイン状態。
  const AccountAuthState.loggedOut({required this.source})
    : hasSession = false,
      isLoggedIn = false,
      isVerified = false,
      accountId = null,
      displayName = null;

  /// 対象サイト。
  final NovelSource source;

  /// 保存済みのセッション情報があるか。
  final bool hasSession;

  /// セッションが有効と確認済みか。
  final bool isLoggedIn;

  /// 保存済みの認証情報をサイトが受け付けたことを確認できたか。
  final bool isVerified;

  /// サイト上のアカウント識別子。取得できないサイトでは `null`。
  final String? accountId;

  /// UIに表示できるアカウント名。取得できないサイトでは `null`。
  final String? displayName;
}
