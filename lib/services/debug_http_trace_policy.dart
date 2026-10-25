import 'package:novelty/sites/novel_source.dart';

/// 開発用HTTP Traceを許可する公式サイトのホストを管理する。
class DebugHttpTracePolicy {
  const DebugHttpTracePolicy._();

  static const Map<NovelSource, Set<String>> _hostsBySource =
      <NovelSource, Set<String>>{
        NovelSource.narou: <String>{'syosetu.com'},
        NovelSource.kakuyomu: <String>{'kakuyomu.jp'},
        NovelSource.alphapolis: <String>{'alphapolis.co.jp'},
        NovelSource.hameln: <String>{'syosetu.org'},
        NovelSource.estar: <String>{'estar.jp'},
        NovelSource.novelup: <String>{'novelup.plus'},
      };

  /// サイトの公式ホストとサブドメインを返す。
  static Set<String> hostsFor(NovelSource source) => _hostsBySource[source]!;

  /// HTTPSの公式ホストからサイト種別を解決する。
  static NovelSource? sourceForUrl(String rawUrl) {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || uri.scheme != 'https' || !uri.hasAuthority) return null;
    if (uri.userInfo.isNotEmpty) return null;

    final host = uri.host.toLowerCase();
    for (final entry in _hostsBySource.entries) {
      if (_matchesHost(host, entry.value)) return entry.key;
    }
    return null;
  }

  /// URLが指定サイトのHTTPS公式ホストか確認する。
  static bool isTrustedUrl(String rawUrl, NovelSource source) =>
      sourceForUrl(rawUrl) == source;

  static bool _matchesHost(String host, Set<String> trustedHosts) =>
      trustedHosts.any(
        (trustedHost) => host == trustedHost || host.endsWith('.$trustedHost'),
      );
}
