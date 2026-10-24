import 'package:novelty/utils/trusted_uri.dart';

final RegExp _hamelnNumericIdPattern = RegExp(r'^\d+$');

/// ハーメルンが利用するHTTPS originか判定する。
bool isTrustedHamelnUri(Uri uri) =>
    isTrustedHttpsOrigin(uri, host: 'syosetu.org') ||
    isTrustedHttpsOrigin(uri, host: 'h.syosetu.org');

/// robots.txtで取得が禁止されているハーメルンURLか判定する。
bool isHamelnRobotsDisallowedUri(Uri uri) {
  final mode = uri.queryParameters['mode'];
  return uri.path.startsWith('/conv/pdf/') ||
      (mode != null && _isHamelnRobotsDisallowedMode(mode));
}

/// ハーメルンのHTTPS originとrobots.txtの取得制限を検証する。
bool isAllowedHamelnNavigationUri(Uri? uri) =>
    uri != null && isTrustedHamelnUri(uri) && !isHamelnRobotsDisallowedUri(uri);

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
  if (uri == null || !isTrustedHamelnUri(uri)) {
    throw FormatException('ハーメルン公式HTTPS URLではありません: $url');
  }
  return uri;
}

bool _isHamelnRobotsDisallowedMode(String mode) {
  if (<String>{
    'seek_list',
    'ss_analyze',
    'ss_detail_like',
    'rating_input',
    'ss_config',
    'review_vote',
    'recommended_vote',
    'recommended_redirect',
    'url_jump',
  }.contains(mode)) {
    return true;
  }
  return RegExp(
    '^(?:ss_detail[3-6]|tuho_|siori2_|favo_|message_|correct_)',
  ).hasMatch(mode);
}

void _validateNumericId(String value, String label) {
  if (!_hamelnNumericIdPattern.hasMatch(value)) {
    throw FormatException('ハーメルンの$labelは数字で指定してください');
  }
}
