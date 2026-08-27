import 'dart:convert';

import 'package:html/parser.dart' as html_parser;
import 'package:novelty/models/remote_library_entry.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:novelty/utils/alphapolis_uri.dart';

/// お気に入り一覧1ページを解析した結果。
class AlphapolisFavoritePage {
  /// コンストラクタ。
  const AlphapolisFavoritePage({
    required this.entries,
    required this.currentPage,
    required this.lastPage,
  });

  /// このページに含まれる作品。
  final List<RemoteLibraryEntry> entries;

  /// このページの番号。
  final int currentPage;

  /// 最終ページ番号。
  final int lastPage;
}

/// アルファポリスのお気に入り一覧HTMLを解析する。
///
/// 一覧本体はVueへ渡すJSONとして `#app-favorite-content` 直下の
/// `script[type="application/json"]` に埋め込まれている。DOMの見た目に
/// 依存せず、このJSONだけを読む。
class AlphapolisFavoriteParser {
  /// 一覧JSONを埋め込んでいる要素。
  static const _jsonSelector =
      '#app-favorite-content script[type="application/json"]';

  static final RegExp _workPathPattern = RegExp(r'^/novel/(\d+)/(\d+)$');

  /// HTMLを解析する。
  AlphapolisFavoritePage parse(String html) {
    final document = html_parser.parse(html);
    final script = document.querySelector(_jsonSelector);
    if (script == null) {
      throw const FormatException('お気に入り一覧のJSONが見つかりません');
    }

    final decoded = json.decode(script.text);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('お気に入り一覧のJSONがオブジェクトではありません');
    }

    final paginator = decoded['paginator'];
    if (paginator is! Map<String, dynamic>) {
      throw const FormatException('お気に入り一覧のpaginatorが見つかりません');
    }

    final items = paginator['items'];
    final entriesById = <String, RemoteLibraryEntry>{};
    if (items is List<dynamic>) {
      for (final item in items) {
        final entry = _parseEntry(item);
        if (entry == null) continue;
        entriesById.putIfAbsent(entry.workId, () => entry);
      }
    }

    return AlphapolisFavoritePage(
      entries: entriesById.values.toList(growable: false),
      currentPage: _positiveInt(paginator['currentPage']) ?? 1,
      lastPage: _positiveInt(paginator['lastPage']) ?? 1,
    );
  }

  RemoteLibraryEntry? _parseEntry(dynamic item) {
    if (item is! Map<String, dynamic>) return null;

    final content = item['content'];
    if (content is! Map<String, dynamic>) return null;

    final url = content['url'];
    if (url is! String) return null;
    final match = _workPathPattern.firstMatch(Uri.parse(url).path);
    if (match == null) return null;

    final user = item['user'];
    return RemoteLibraryEntry(
      source: NovelSource.alphapolis,
      workId: buildAlphapolisWorkId(match.group(1)!, match.group(2)!),
      title: _nonEmpty(content['title']),
      writer: user is Map<String, dynamic> ? _nonEmpty(user['name']) : null,
    );
  }

  String? _nonEmpty(dynamic value) {
    if (value is! String) return null;
    final trimmed = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  int? _positiveInt(dynamic value) {
    if (value is int) return value > 0 ? value : null;
    if (value is String) {
      final parsed = int.tryParse(value);
      return parsed != null && parsed > 0 ? parsed : null;
    }
    return null;
  }
}
