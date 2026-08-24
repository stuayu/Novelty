final RegExp _hamelnNumericIdPattern = RegExp(r'^\d+$');

/// ハーメルンの作品URLを組み立てる。
String buildHamelnWorkUrl(String workId) {
  _validateNumericId(workId, '作品ID');
  return 'https://syosetu.org/novel/$workId/';
}

/// ハーメルンの作品IDとサイト固有話数から本文URLを組み立てる。
String buildHamelnEpisodeUrl(String workId, String episodeNumber) {
  _validateNumericId(episodeNumber, '話数');
  return '${buildHamelnWorkUrl(workId)}$episodeNumber.html';
}

/// ハーメルンの作品URLまたは本文URLから作品IDを抽出する。
String extractHamelnWorkId(String url) {
  final uri = _parseOfficialUri(url);
  final segments = uri.pathSegments
      .where((segment) => segment.isNotEmpty)
      .toList();
  if ((segments.length != 2 && segments.length != 3) ||
      segments.first != 'novel' ||
      !_hamelnNumericIdPattern.hasMatch(segments[1]) ||
      (segments.length == 3 && !RegExp(r'^\d+\.html$').hasMatch(segments[2]))) {
    throw FormatException('ハーメルンの作品URLではありません: $url');
  }
  return segments[1];
}

/// ハーメルンの本文URLからサイト固有話数を抽出する。
String extractHamelnEpisodeNumber(String url) {
  final uri = _parseOfficialUri(url);
  extractHamelnWorkId(url);
  final segments = uri.pathSegments
      .where((segment) => segment.isNotEmpty)
      .toList();
  if (segments.length != 3) {
    throw FormatException('ハーメルンの本文URLではありません: $url');
  }
  return segments[2].replaceFirst('.html', '');
}

Uri _parseOfficialUri(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null ||
      uri.scheme != 'https' ||
      (uri.host != 'syosetu.org' && uri.host != 'h.syosetu.org')) {
    throw FormatException('ハーメルン公式HTTPS URLではありません: $url');
  }
  return uri;
}

void _validateNumericId(String value, String label) {
  if (!_hamelnNumericIdPattern.hasMatch(value)) {
    throw FormatException('ハーメルンの$labelは数字で指定してください');
  }
}
