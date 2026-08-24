final RegExp _estarNumericIdPattern = RegExp(r'^\d+$');

/// エブリスタの作品URLを組み立てる。
String buildEstarWorkUrl(String workId) {
  _validateEstarWorkId(workId);
  return 'https://estar.jp/novels/$workId';
}

/// エブリスタの作品IDと開始ページから本文URLを組み立てる。
String buildEstarEpisodeUrl(String workId, int pageNo) {
  if (pageNo < 1) {
    throw ArgumentError.value(pageNo, 'pageNo', '1以上で指定してください');
  }
  return '${buildEstarWorkUrl(workId)}/viewer?page=$pageNo';
}

/// エブリスタの作品URLまたは本文URLから作品IDを抽出する。
String extractEstarWorkId(String url) {
  final uri = _parseEstarOfficialUri(url);
  final segments = uri.pathSegments
      .where((segment) => segment.isNotEmpty)
      .toList();
  if ((segments.length != 2 && segments.length != 3) ||
      segments.first != 'novels' ||
      !_estarNumericIdPattern.hasMatch(segments[1]) ||
      (segments.length == 3 && segments[2] != 'viewer')) {
    throw FormatException('エブリスタの作品URLではありません: $url');
  }
  return segments[1];
}

/// エブリスタの本文URLから開始ページを抽出する。
int extractEstarEpisodePageNo(String url) {
  final uri = _parseEstarOfficialUri(url);
  extractEstarWorkId(url);
  final segments = uri.pathSegments
      .where((segment) => segment.isNotEmpty)
      .toList();
  final pageNo = int.tryParse(uri.queryParameters['page'] ?? '');
  if (segments.length != 3 ||
      segments.last != 'viewer' ||
      pageNo == null ||
      pageNo < 1) {
    throw FormatException('エブリスタの本文URLではありません: $url');
  }
  return pageNo;
}

Uri _parseEstarOfficialUri(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https' || uri.host != 'estar.jp') {
    throw FormatException('エブリスタ公式HTTPS URLではありません: $url');
  }
  return uri;
}

void _validateEstarWorkId(String workId) {
  if (!_estarNumericIdPattern.hasMatch(workId)) {
    throw const FormatException('エブリスタ作品IDは数字で指定してください');
  }
}
