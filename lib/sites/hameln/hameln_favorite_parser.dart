import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:novelty/models/remote_library_entry.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:novelty/utils/hameln_uri.dart';

/// ハーメルンのお気に入り一覧を解析する。
class HamelnFavoriteParser {
  /// コンストラクタ。
  const HamelnFavoriteParser();

  static final _zeroFavoritesPattern = RegExp(r'一覧\s*[：:]\s*0件');

  /// お気に入りページのHTMLから作品一覧を取得する。
  List<RemoteLibraryEntry> parse(String html) {
    final document = html_parser.parse(html);
    final favoriteList = document.querySelector('#favo_list, .favo_list');
    if (favoriteList == null) {
      if (_zeroFavoritesPattern.hasMatch(document.body?.text ?? '')) {
        return const <RemoteLibraryEntry>[];
      }
      throw const FormatException('ハーメルンのお気に入り一覧が見つかりません');
    }

    final entries = <String, RemoteLibraryEntry>{};
    for (final row in favoriteList.querySelectorAll('[id^="favo-id"]')) {
      final workLink = _findWorkLink(row);
      if (workLink == null) continue;

      final workId = workLink.$1;
      entries.putIfAbsent(
        workId,
        () => RemoteLibraryEntry(
          source: NovelSource.hameln,
          workId: workId,
          title: _normalizeText(workLink.$2),
          writer: _findAuthor(row),
        ),
      );
    }
    return entries.values.toList(growable: false);
  }

  (String, String)? _findWorkLink(Element row) {
    for (final link in row.querySelectorAll('a[href]')) {
      final href = link.attributes['href'];
      if (href == null || href.isEmpty) continue;
      final uri = Uri.tryParse(href);
      if (uri == null) continue;

      final absoluteUri = Uri.parse('https://syosetu.org/').resolveUri(uri);
      if (!isTrustedHamelnUri(absoluteUri) ||
          absoluteUri.pathSegments.where((part) => part.isNotEmpty).length !=
              2) {
        continue;
      }
      try {
        final workId = extractHamelnWorkId(absoluteUri.toString());
        final title = _normalizeText(link.text);
        if (title.isNotEmpty) return (workId, title);
      } on FormatException {
        continue;
      }
    }
    return null;
  }

  String? _findAuthor(Element row) {
    for (final link in row.querySelectorAll('a[href]')) {
      final href = link.attributes['href'];
      if (href == null || href.isEmpty) continue;
      final uri = Uri.parse('https://syosetu.org/').resolve(href);
      if (isTrustedHamelnUri(uri) &&
          RegExp(r'^/user/\d+/?$').hasMatch(uri.path)) {
        final name = _normalizeText(link.text);
        if (name.isNotEmpty) return name;
      }
    }
    return null;
  }

  String _normalizeText(String text) =>
      text.replaceAll(RegExp(r'\s+'), ' ').trim();
}
