import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:novelty/sites/novel_source.dart';

/// カクヨム閲覧履歴の1件。
class KakuyomuHistoryEntry {
  /// コンストラクタ。
  const KakuyomuHistoryEntry({
    required this.source,
    required this.workId,
    this.episodeId,
    this.resumeReadingUrl,
    this.title,
    this.episodeTitle,
    this.lastReadAt,
  });

  /// 提供サイト。
  final NovelSource source;

  /// 作品ID。
  final String workId;

  /// カクヨムのリモートエピソードID。
  final String? episodeId;

  /// サイト側の続きから読むURL。実HTMLではここから話IDを解決する。
  final Uri? resumeReadingUrl;

  /// 作品タイトル。
  final String? title;

  /// エピソードタイトル。
  final String? episodeTitle;

  /// サイト側の最終閲覧日時。
  final DateTime? lastReadAt;
}

/// カクヨム閲覧履歴ページの解析結果。
class KakuyomuHistoryPage {
  /// コンストラクタ。
  const KakuyomuHistoryPage({
    required this.entries,
    required this.isGuestPage,
    this.nextPageUrl,
  });

  /// 履歴一覧。
  final List<KakuyomuHistoryEntry> entries;

  /// 未ログイン向けguestページか。
  final bool isGuestPage;

  /// 次ページURL。
  final Uri? nextPageUrl;
}

/// カクヨム閲覧履歴HTMLを解析する。
class KakuyomuHistoryParser {
  static final RegExp _workPathPattern = RegExp(r'^/works/([0-9]+)(?:/|$)');
  static final RegExp _episodePathPattern = RegExp(
    r'^/works/([0-9]+)/episodes/([0-9]+)(?:/|$)',
  );

  /// HTMLを解析する。
  KakuyomuHistoryPage parse(
    String html, {
    required Uri baseUri,
    DateTime? now,
  }) {
    final document = html_parser.parse(html);
    final entries = <KakuyomuHistoryEntry>[];
    final seen = <String>{};

    for (final item in document.querySelectorAll(
      'li.widget-antennaList-item',
    )) {
      final workId = _findWorkId(item);
      final episode = _findEpisode(item, workId);
      final resumeReadingUrl = _findResumeReadingUrl(item, baseUri);
      if (workId == null || (episode == null && resumeReadingUrl == null)) {
        continue;
      }

      final key = '$workId:${episode?.episodeId ?? resumeReadingUrl}';
      if (!seen.add(key)) continue;
      entries.add(
        KakuyomuHistoryEntry(
          source: NovelSource.kakuyomu,
          workId: workId,
          episodeId: episode?.episodeId,
          resumeReadingUrl: resumeReadingUrl,
          title: _normalizedText(
            item.querySelector('h4.widget-antennaList-title'),
          ),
          episodeTitle: _normalizedText(
            item.querySelector('a.widget-antennaList-continueReading'),
          ),
          lastReadAt: _findLastReadAt(item, now: now),
        ),
      );
    }

    return KakuyomuHistoryPage(
      entries: entries,
      isGuestPage: _isGuestPage(document),
      nextPageUrl: _findNextPage(document, baseUri),
    );
  }

  Uri? _findResumeReadingUrl(Element item, Uri baseUri) {
    final anchor = item.querySelector('a.widget-antennaList-continueReading');
    final href = anchor?.attributes['href'];
    if (href == null || href.isEmpty) return null;
    final resolved = baseUri.resolve(href);
    if (resolved.host != 'kakuyomu.jp' ||
        !resolved.path.endsWith('/resume_reading')) {
      return null;
    }
    return resolved;
  }

  bool _isGuestPage(Document document) {
    final htmlElement = document.querySelector('html');
    return htmlElement?.attributes['data-is-guest'] == '1' ||
        document.querySelector('#page-my-antenna-readingHistoriesGuest') !=
            null ||
        document.querySelector('a[href^="/auth/login"]') != null;
  }

  String? _findWorkId(Element item) {
    for (final anchor in item.querySelectorAll('a[href]')) {
      final href = anchor.attributes['href'];
      final uri = href == null ? null : Uri.tryParse(href);
      if (uri == null || (uri.hasAuthority && uri.host != 'kakuyomu.jp')) {
        continue;
      }
      final match = _workPathPattern.firstMatch(uri.path);
      if (match != null) return match.group(1);
    }
    return null;
  }

  ({String episodeId, String workId})? _findEpisode(
    Element item,
    String? workId,
  ) {
    for (final anchor in item.querySelectorAll('a[href]')) {
      final href = anchor.attributes['href'];
      final uri = href == null ? null : Uri.tryParse(href);
      if (uri == null || (uri.hasAuthority && uri.host != 'kakuyomu.jp')) {
        continue;
      }
      final match = _episodePathPattern.firstMatch(uri.path);
      if (match == null || match.group(1) != workId) continue;
      return (workId: match.group(1)!, episodeId: match.group(2)!);
    }
    return null;
  }

  DateTime? _findLastReadAt(Element item, {DateTime? now}) {
    for (final time in item.querySelectorAll('time')) {
      final value = time.attributes['datetime'] ?? time.text.trim();
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
    }
    final eventText = item
        .querySelector('ul.widget-antennaList-event')
        ?.text
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final match = eventText == null
        ? null
        : RegExp(r'(\d{1,2})月(\d{1,2})日閲覧').firstMatch(eventText);
    if (match != null) {
      final reference = now ?? DateTime.now();
      return DateTime(
        reference.year,
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
      );
    }
    return null;
  }

  Uri? _findNextPage(Document document, Uri baseUri) {
    final icon = document.querySelector('a i.icon-next-large');
    final href = icon?.parent?.attributes['href'];
    if (href == null || href.isEmpty) return null;
    final resolved = baseUri.resolve(href);
    if (resolved.host != 'kakuyomu.jp' ||
        resolved.path != '/my/antenna/reading_histories') {
      return null;
    }
    return resolved;
  }

  String? _normalizedText(Element? element) {
    final value = element?.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return value == null || value.isEmpty ? null : value;
  }
}
