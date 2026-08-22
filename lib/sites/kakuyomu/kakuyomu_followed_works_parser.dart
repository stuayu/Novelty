import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:novelty/models/remote_library_entry.dart';
import 'package:novelty/sites/novel_source.dart';

/// カクヨムのフォロー作品一覧1ページを解析した結果。
class KakuyomuFollowedWorksPage {
  /// コンストラクタ。
  const KakuyomuFollowedWorksPage({
    required this.entries,
    this.nextPageUrl,
  });

  /// このページに含まれる作品。
  final List<RemoteLibraryEntry> entries;

  /// 次ページURL。最終ページではnull。
  final Uri? nextPageUrl;
}

/// カクヨムのフォロー作品一覧HTMLを解析する。
class KakuyomuFollowedWorksParser {
  /// 一覧ページの作品行。
  static const _itemSelector = 'li.widget-antennaList-item';

  /// 一覧ページの作品タイトル。
  static const _titleSelector = 'h4.widget-antennaList-title';

  static final RegExp _workPathPattern = RegExp(r'^/works/([0-9]+)(?:/|$)');

  /// HTMLを解析する。
  KakuyomuFollowedWorksPage parse(String html, {required Uri baseUri}) {
    final document = html_parser.parse(html);
    final entriesById = <String, RemoteLibraryEntry>{};

    for (final item in document.querySelectorAll(_itemSelector)) {
      final workId = _findWorkId(item);
      if (workId == null) continue;

      final title = _normalizedText(item.querySelector(_titleSelector));
      entriesById.putIfAbsent(
        workId,
        () => RemoteLibraryEntry(
          source: NovelSource.kakuyomu,
          workId: workId,
          title: title,
        ),
      );
    }

    return KakuyomuFollowedWorksPage(
      entries: entriesById.values.toList(growable: false),
      nextPageUrl: _findNextPage(document, baseUri),
    );
  }

  String? _findWorkId(Element item) {
    for (final anchor in item.querySelectorAll('a[href]')) {
      final href = anchor.attributes['href'];
      if (href == null) continue;
      final uri = Uri.tryParse(href);
      if (uri == null) continue;
      if (uri.hasAuthority && uri.host != 'kakuyomu.jp') continue;
      final match = _workPathPattern.firstMatch(uri.path);
      if (match != null) return match.group(1);
    }
    return null;
  }

  Uri? _findNextPage(Document document, Uri baseUri) {
    final icon = document.querySelector('a i.icon-next-large');
    final anchor = icon?.parent;
    final href = anchor?.attributes['href'];
    if (href == null || href.isEmpty) return null;

    final resolved = baseUri.resolve(href);
    if (resolved.host != 'kakuyomu.jp') return null;
    if (!resolved.path.startsWith('/my/antenna/works')) return null;
    return resolved;
  }

  String? _normalizedText(Element? element) {
    final value = element?.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return value == null || value.isEmpty ? null : value;
  }
}
