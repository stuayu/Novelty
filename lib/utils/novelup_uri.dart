final RegExp _novelupNumericIdPattern = RegExp(r'^\d+$');

/// ノベルアップ＋の作品URLを組み立てる。
String buildNovelupWorkUrl(String workId) {
  _validateNovelupId(workId, '作品ID');
  return 'https://novelup.plus/story/$workId';
}

/// ノベルアップ＋の作品IDとサイト固有エピソードIDから本文URLを組み立てる。
String buildNovelupEpisodeUrl(String workId, String episodeId) {
  _validateNovelupId(episodeId, 'エピソードID');
  return '${buildNovelupWorkUrl(workId)}/$episodeId';
}

/// ノベルアップ＋の作品URLまたは本文URLから作品IDを抽出する。
String extractNovelupWorkId(String url) {
  final uri = _parseNovelupOfficialUri(url);
  final segments = uri.pathSegments
      .where((segment) => segment.isNotEmpty)
      .toList();
  if ((segments.length != 2 && segments.length != 3) ||
      segments.first != 'story' ||
      !_novelupNumericIdPattern.hasMatch(segments[1]) ||
      (segments.length == 3 &&
          !_novelupNumericIdPattern.hasMatch(segments[2]))) {
    throw FormatException('ノベルアップ＋の作品URLではありません: $url');
  }
  return segments[1];
}

/// ノベルアップ＋の本文URLからサイト固有エピソードIDを抽出する。
String extractNovelupEpisodeId(String url) {
  final uri = _parseNovelupOfficialUri(url);
  extractNovelupWorkId(url);
  final segments = uri.pathSegments
      .where((segment) => segment.isNotEmpty)
      .toList();
  if (segments.length != 3) {
    throw FormatException('ノベルアップ＋の本文URLではありません: $url');
  }
  return segments[2];
}

Uri _parseNovelupOfficialUri(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https' || uri.host != 'novelup.plus') {
    throw FormatException('ノベルアップ＋公式HTTPS URLではありません: $url');
  }
  return uri;
}

void _validateNovelupId(String value, String label) {
  if (!_novelupNumericIdPattern.hasMatch(value)) {
    throw FormatException('ノベルアップ＋の$labelは数字で指定してください');
  }
}
