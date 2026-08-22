/// カクヨムの認証済みWebセッションとして信頼できるURLか判定する。
///
/// OAuth中は外部サイトへ遷移するため、それらのページではログイン完了判定や
/// Cookie取り込みを行わない。HTTPSの公式メインホストだけを許可する。
bool isTrustedKakuyomuUri(Uri uri) {
  return uri.scheme.toLowerCase() == 'https' &&
      uri.host.toLowerCase() == 'kakuyomu.jp';
}

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
