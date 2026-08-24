/// アルファポリスのアプリ内作品IDを構成する要素。
typedef AlphapolisWorkIdParts = ({String authorId, String siteWorkId});

final RegExp _numericIdPattern = RegExp(r'^\d+$');

/// authorIdとサイト側workIdからアプリ内workIdを組み立てる。
String buildAlphapolisWorkId(String authorId, String siteWorkId) {
  if (!_numericIdPattern.hasMatch(authorId) ||
      !_numericIdPattern.hasMatch(siteWorkId)) {
    throw const FormatException('アルファポリス作品IDは数字2要素で指定してください');
  }
  return '$authorId-$siteWorkId';
}

/// アプリ内workIdをauthorIdとサイト側workIdへ分解する。
AlphapolisWorkIdParts splitAlphapolisWorkId(String workId) {
  final match = RegExp(r'^(\d+)-(\d+)$').firstMatch(workId);
  if (match == null) {
    throw const FormatException('アルファポリス作品IDは数字2要素で指定してください');
  }
  return (authorId: match.group(1)!, siteWorkId: match.group(2)!);
}

/// アプリ内workIdからアルファポリスの作品URLを組み立てる。
String buildAlphapolisWorkUrl(String workId) {
  final parts = splitAlphapolisWorkId(workId);
  return 'https://www.alphapolis.co.jp/novel/'
      '${parts.authorId}/${parts.siteWorkId}';
}

/// アプリ内workIdとサイト固有episodeNoから本文URLを組み立てる。
String buildAlphapolisEpisodeUrl(String workId, String episodeNo) {
  if (!_numericIdPattern.hasMatch(episodeNo)) {
    throw const FormatException('アルファポリスのepisodeNoは数字で指定してください');
  }
  return '${buildAlphapolisWorkUrl(workId)}/episode/$episodeNo';
}
