import 'package:novelty/utils/trusted_uri.dart';

/// カクヨムの認証済みWebセッションとして信頼できるURLか判定する。
///
/// OAuth中は外部サイトへ遷移するため、それらのページではログイン完了判定や
/// Cookie取り込みを行わない。HTTPSの公式メインホストだけを許可する。
bool isTrustedKakuyomuUri(Uri uri) {
  return isTrustedHttpsOrigin(uri, host: 'kakuyomu.jp');
}

/// ログイン確認エラーを表示してよい、ログイン後のサイト画面か判定する。
bool shouldShowKakuyomuLoginCheckError(String pagePath) {
  if (pagePath == 'unknown' || pagePath == 'external') return false;

  const nonCompletionPaths = <String>[
    '/auth/',
    '/login',
    '/signup',
    '/register',
    '/users/sign_up',
    '/users/password',
    '/password/',
  ];
  return !nonCompletionPaths.any(pagePath.startsWith);
}

/// ログイン送信後かつログイン完了先へ遷移した場合に確認を開始する。
bool shouldCheckKakuyomuLoginAfterNavigation({
  required bool loginAttempted,
  required String pagePath,
}) => loginAttempted && shouldShowKakuyomuLoginCheckError(pagePath);

/// 認証に失敗してログインフォームへ戻った場合、送信フラグを消す。
bool shouldResetKakuyomuLoginAttempt(String pagePath) =>
    const <String>['/auth/login', '/login'].any(
      (loginPath) =>
          pagePath == loginPath || pagePath.startsWith('$loginPath/'),
    );

/// 保存済みカクヨムepisode URLから実際のepisode IDを抽出する。
///
/// 話数からIDを推測せず、目次取得時に保存したURLだけを信頼する。
/// 絶対URLでは公式HTTPSホストを必須とし、相対URLも同一作品のepisode path
/// だけを受け付ける。
String? extractKakuyomuEpisodeId({
  required String workId,
  required String url,
}) {
  if (!RegExp(r'^\d+$').hasMatch(workId)) return null;

  final uri = Uri.tryParse(url);
  if (uri == null) return null;
  if (uri.hasAuthority && !isTrustedKakuyomuUri(uri)) return null;

  final segments = uri.pathSegments;
  if (segments.length != 4 ||
      segments[0] != 'works' ||
      segments[1] != workId ||
      segments[2] != 'episodes') {
    return null;
  }

  final episodeId = segments[3];
  return RegExp(r'^\d+$').hasMatch(episodeId) ? episodeId : null;
}
