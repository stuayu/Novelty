import 'dart:convert';

import 'package:alphapolis_parser/alphapolis_parser.dart';
import 'package:dio/dio.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:novelty/models/episode.dart';
import 'package:novelty/models/novel_info.dart';
import 'package:novelty/models/novel_search_query.dart';
import 'package:novelty/models/novel_search_result.dart';
import 'package:novelty/models/ranking_page.dart';
import 'package:novelty/services/http_client.dart';
import 'package:novelty/sites/novel_site.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:novelty/utils/alphapolis_uri.dart';
import 'package:novelty/utils/request_rate_limiter.dart';

/// アルファポリスへのHTTP取得に失敗した場合の例外。
class AlphapolisHttpException implements Exception {
  /// コンストラクタ。
  const AlphapolisHttpException(this.statusCode, this.url);

  /// HTTPステータスコード。
  final int statusCode;

  /// リクエストURL。
  final String url;

  @override
  String toString() => 'AlphapolisHttpException($statusCode): $url';
}

/// アルファポリスのサイト定義。
class AlphapolisSite implements NovelSite {
  /// コンストラクタ。
  AlphapolisSite({Dio? dio, RequestRateLimiter? rateLimiter})
    : _dio = _createRateLimitedDio(
        dio,
        rateLimiter ?? RequestRateLimiter(interval: const Duration(seconds: 1)),
      );

  final Dio _dio;

  static Dio _createRateLimitedDio(
    Dio? dio,
    RequestRateLimiter rateLimiter,
  ) {
    return dio == null
        ? createNoveltyDio(rateLimiter: rateLimiter)
        : attachNoveltyRateLimiter(dio, rateLimiter);
  }

  @override
  NovelSource get source => NovelSource.alphapolis;

  @override
  List<NovelContentElement> parseEpisodeBody(String html) {
    return parseAlphapolisEpisodeBody(html);
  }

  @override
  String? metaText(NovelInfo info) {
    final point = info.allPoint;
    return point == null ? null : '${_formatWithComma(point)} pt';
  }

  static String _formatWithComma(int value) {
    return value.toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
  }

  @override
  List<GenreMaster> get genres => const <GenreMaster>[
    GenreMaster(id: '110100', name: 'ミステリー'),
    GenreMaster(id: '110200', name: 'ホラー'),
    GenreMaster(id: '110300', name: 'SF'),
    GenreMaster(id: '110400', name: 'ファンタジー'),
    GenreMaster(id: '110500', name: '恋愛'),
    GenreMaster(id: '110600', name: '青春'),
    GenreMaster(id: '110700', name: '現代文学'),
    GenreMaster(id: '110800', name: '大衆娯楽'),
    GenreMaster(id: '111000', name: '経済・企業'),
    GenreMaster(id: '111100', name: '歴史・時代'),
    GenreMaster(id: '111200', name: '児童書・童話'),
    GenreMaster(id: '111300', name: '絵本'),
    GenreMaster(id: '111400', name: 'キャラ文芸'),
    GenreMaster(id: '111500', name: 'ライト文芸'),
    GenreMaster(id: '111600', name: 'ｴｯｾｲ・ﾉﾝﾌｨｸｼｮﾝ'),
    GenreMaster(id: '119000', name: 'BL'),
  ];

  @override
  List<RankingTypeMaster> get rankingTypes => const <RankingTypeMaster>[
    RankingTypeMaster(id: 'completed', label: '最近完結', urlPath: 'completed'),
    RankingTypeMaster(id: '24hpt', label: '24h', urlPath: '24hpt'),
    RankingTypeMaster(
      id: 'episode_recent',
      label: '最近更新',
      urlPath: 'episode_recent',
    ),
    RankingTypeMaster(id: 'weekly', label: '週間', urlPath: 'weekly'),
    RankingTypeMaster(id: 'monthly', label: '月間', urlPath: 'monthly'),
    RankingTypeMaster(id: 'yearly', label: '年間', urlPath: 'yearly'),
    RankingTypeMaster(id: 'total', label: '累計', urlPath: 'total'),
    RankingTypeMaster(id: 'favorite', label: 'お気に入り', urlPath: 'favorite'),
    RankingTypeMaster(id: 'comment', label: '感想', urlPath: 'comment'),
    RankingTypeMaster(id: 'char', label: '文字数', urlPath: 'char'),
    RankingTypeMaster(id: 'recent', label: '新着', urlPath: 'recent'),
    RankingTypeMaster(
      id: 'episode_old',
      label: '更新が古い順',
      urlPath: 'episode_old',
    ),
  ];

  @override
  Future<NovelInfo> fetchNovelInfo(String workId) async {
    final html = await _getHtml(buildAlphapolisWorkUrl(workId));
    final document = html_parser.parse(html);
    final data = _parseCoverData(document);
    final chapterEpisodes = _chapterEpisodes(data);
    final episodeCount = _episodeCount(chapterEpisodes);
    final completedAt = _detailValue(document, '初回完結日時');
    final genreHref = document
        .querySelector('[href*="category_ids="]')
        ?.attributes['href'];
    final genreId = genreHref == null
        ? null
        : RegExp(r'category_ids=(\d+)').firstMatch(genreHref)?.group(1);
    final content = data['content'] as Map<String, dynamic>?;
    final user = content?['user'] as Map<String, dynamic>?;

    return NovelInfo(
      source: NovelSource.alphapolis,
      workId: workId,
      title: document
          .querySelector('.p-content-info__title.is-novel')
          ?.text
          .trim(),
      writer:
          user?['name'] as String? ??
          document.querySelector('.p-content-info__author')?.text.trim(),
      story: document.querySelector('.p-content-info__abstract')?.text.trim(),
      genreId: genreId,
      // なろうの意味論: 1=連載中、0=短編または完結。
      end: completedAt == null ? 1 : 0,
      novelType: episodeCount == 1 ? 2 : 1,
      generalAllNo: episodeCount,
      totalCharacterCount: _parseNumber(_detailValue(document, '文字数')),
      allPoint: _parseNumber(
        document.querySelector('.c-point--24h span')?.text,
      ),
      followCount: _parseNumber(
        document.querySelector('.p-content-info__meta-heart')?.text,
      ),
      keyword: document
          .querySelectorAll('.p-content-info__tags .c-tag a')
          .map((element) => element.text.trim())
          .where((text) => text.isNotEmpty)
          .join(' '),
      generalFirstup: _normalizeDateTime(
        _detailValue(document, '初回公開日時'),
      ),
      generalLastup: _normalizeDateTime(_detailValue(document, '更新日時')),
    );
  }

  @override
  Future<List<Episode>> fetchToc(String workId) async {
    final html = await _getHtml(buildAlphapolisWorkUrl(workId));
    final document = html_parser.parse(html);
    final chapters = _chapterEpisodes(_parseCoverData(document));
    final episodes = <Episode>[];
    for (final chapter in chapters) {
      final chapterMap = chapter as Map<String, dynamic>;
      final chapterItems = chapterMap['episodes'] as List<dynamic>?;
      if (chapterItems == null) {
        throw const FormatException('chapterEpisodes内にepisodesがありません');
      }
      for (final item in chapterItems) {
        final episode = item as Map<String, dynamic>;
        final href = episode['url'] as String?;
        final title = episode['mainTitle'] as String?;
        if (href == null || title == null) {
          throw const FormatException('目次の必須項目がありません');
        }
        episodes.add(
          Episode(
            source: NovelSource.alphapolis,
            index: episodes.length + 1,
            subtitle: title,
            url: Uri.parse(source.baseUrl).resolve(href).toString(),
            update: _normalizeDateTime(episode['upTime'] as String?),
          ),
        );
      }
    }
    if (episodes.isEmpty) {
      throw const FormatException('chapterEpisodesにエピソードがありません');
    }
    return episodes;
  }

  @override
  Future<Episode> fetchEpisode(String workId, int index, {String? url}) async {
    final episodeUrl = url ?? await _resolveEpisodeUrl(workId, index);
    final episodeNo = _episodeNoFromUrl(workId, episodeUrl);
    final pageResponse = await _getResponse(episodeUrl);
    final pageHtml = pageResponse.data ?? '';
    final document = html_parser.parse(pageHtml);
    final scripts = document
        .querySelectorAll('script')
        .map((element) => element.text)
        .join('\n');
    final csrf = RegExp(
      r'''["']X-CSRF-TOKEN["']\s*:\s*["']([^"']+)["']''',
    ).firstMatch(scripts)?.group(1);
    final token = RegExp(
      r'''["']token["']\s*:\s*["']([0-9a-f]{32})["']''',
    ).firstMatch(scripts)?.group(1);
    if (csrf == null || token == null) {
      throw const FormatException('本文取得用のCSRFトークンまたはtokenが見つかりません');
    }

    final cookies = pageResponse.headers['set-cookie']
        ?.map((value) => value.split(';').first.trim())
        .where((value) => value.isNotEmpty)
        .join('; ');
    final bodyUrl = '${source.baseUrl}/novel/episode_body';
    final response = await _dio.post<String>(
      bodyUrl,
      data: Uri(
        queryParameters: <String, String>{
          'episode': episodeNo,
          'token': token,
        },
      ).query,
      options: Options(
        headers: <String, String>{
          'X-CSRF-TOKEN': csrf,
          'Referer': episodeUrl,
          'X-Requested-With': 'XMLHttpRequest',
          Headers.contentTypeHeader:
              'application/x-www-form-urlencoded; charset=UTF-8',
          if (cookies != null && cookies.isNotEmpty) 'Cookie': cookies,
        },
        responseType: ResponseType.plain,
        validateStatus: (_) => true,
      ),
    );
    if (response.statusCode != 200) {
      throw AlphapolisHttpException(response.statusCode ?? -1, bodyUrl);
    }
    final body = response.data ?? '';
    // 空本文やエラーHTMLを成功扱いしない。
    parseEpisodeBody(body);
    return Episode(
      source: NovelSource.alphapolis,
      index: index,
      subtitle: document
          .querySelector('.p-novel-episode__episode-title')
          ?.text
          .trim(),
      url: episodeUrl,
      body: body,
    );
  }

  @override
  Future<NovelSearchResult> searchNovels(NovelSearchQuery query) async {
    final word = query.word?.trim() ?? '';
    final page = ((query.st - 1) ~/ 20) + 1;
    final uri = Uri.parse('${source.baseUrl}/search').replace(
      queryParameters: <String, String>{
        if (word.isNotEmpty) 'query': word,
        'category': 'novel',
        if (query.genreId case final genres? when genres.isNotEmpty)
          'category_ids': genres.first,
        if (page > 1) 'page': '$page',
      },
    );
    final document = html_parser.parse(await _getHtml(uri.toString()));
    final countElement = document.querySelector('.search-count .count');
    if (countElement == null) {
      throw const FormatException('検索結果件数が見つかりません');
    }
    final allCount = _parseNumber(countElement.text);
    if (allCount == null) {
      throw const FormatException('検索結果件数を数値へ変換できません');
    }
    final items = document.querySelectorAll('.section.novels.content-block');
    if (allCount > 0 && items.isEmpty) {
      throw const FormatException('検索結果の作品DOMが見つかりません');
    }
    return NovelSearchResult(
      novels: items.map(_listingToNovelInfo).toList(),
      allCount: allCount,
    );
  }

  @override
  Future<RankingPage> fetchRanking(String rankingType, {int page = 1}) async {
    if (page < 1) {
      throw ArgumentError.value(page, 'page', '1以上で指定してください');
    }
    if (!rankingTypes.any((type) => type.id == rankingType)) {
      throw ArgumentError.value(rankingType, 'rankingType', '未定義のsort値です');
    }
    final uri = Uri.parse('${source.baseUrl}/novel/index').replace(
      queryParameters: <String, String>{
        'sort': rankingType,
        if (page > 1) 'page': '$page',
      },
    );
    final document = html_parser.parse(await _getHtml(uri.toString()));
    final items = document.querySelectorAll('.p-content.is-novel');
    if (items.isEmpty) {
      throw const FormatException('ランキングの作品DOMが見つかりません');
    }
    return RankingPage(
      novels: items.map(_listingToNovelInfo).toList(),
      hasNextPage: _hasNextPage(document, page),
    );
  }

  Future<String> _getHtml(String url) async {
    final response = await _getResponse(url);
    return response.data ?? '';
  }

  Future<Response<String>> _getResponse(String url) async {
    final uri = Uri.parse(url);
    _assertAllowed(uri);
    final response = await _dio.get<String>(
      url,
      options: Options(
        responseType: ResponseType.plain,
        validateStatus: (_) => true,
      ),
    );
    if (response.statusCode != 200) {
      throw AlphapolisHttpException(response.statusCode ?? -1, url);
    }
    return response;
  }

  Future<String> _resolveEpisodeUrl(String workId, int index) async {
    final episodes = await fetchToc(workId);
    final episode = episodes.where((item) => item.index == index).firstOrNull;
    if (episode?.url == null) {
      throw StateError('エピソード $index が見つかりません: $workId');
    }
    return episode!.url!;
  }

  String _episodeNoFromUrl(String workId, String url) {
    final uri = Uri.parse(url);
    _assertAllowed(uri);
    final parts = splitAlphapolisWorkId(workId);
    final segments = uri.pathSegments;
    if (segments.length != 5 ||
        segments[0] != 'novel' ||
        segments[1] != parts.authorId ||
        segments[2] != parts.siteWorkId ||
        segments[3] != 'episode' ||
        !RegExp(r'^\d+$').hasMatch(segments[4])) {
      throw FormatException('作品に属さないエピソードURLです: $url');
    }
    return segments[4];
  }

  void _assertAllowed(Uri uri) {
    if (uri.scheme != 'https' || uri.host != 'www.alphapolis.co.jp') {
      throw StateError('アルファポリス公式HTTPS URLではありません: $uri');
    }
    if (uri.path.startsWith('/dreambookclub/') &&
        !uri.path.startsWith('/dreambookclub/image/')) {
      throw StateError('robots.txtにより取得が禁止されています: ${uri.path}');
    }
  }

  Map<String, dynamic> _parseCoverData(Document document) {
    final script = document.querySelector('script#app-cover-data');
    if (script == null) {
      throw const FormatException('app-cover-dataが見つかりません');
    }
    final decoded = json.decode(script.text);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('app-cover-dataがオブジェクトではありません');
    }
    return decoded;
  }

  List<dynamic> _chapterEpisodes(Map<String, dynamic> data) {
    final chapters = data['chapterEpisodes'];
    if (chapters is! List<dynamic>) {
      throw const FormatException('chapterEpisodesが見つかりません');
    }
    return chapters;
  }

  int _episodeCount(List<dynamic> chapters) {
    var count = 0;
    for (final chapter in chapters) {
      final episodes = (chapter as Map<String, dynamic>)['episodes'];
      if (episodes is! List<dynamic>) {
        throw const FormatException('chapterEpisodes内にepisodesがありません');
      }
      count += episodes.length;
    }
    if (count == 0) {
      throw const FormatException('chapterEpisodesにエピソードがありません');
    }
    return count;
  }

  String? _detailValue(Document document, String label) {
    for (final item in document.querySelectorAll(
      '.p-sidebar-content-info__detail-item',
    )) {
      if (item
              .querySelector('.p-sidebar-content-info__detail-label')
              ?.text
              .trim() ==
          label) {
        return item.children.last.text.trim();
      }
    }
    return null;
  }

  int? _parseNumber(String? value) {
    if (value == null) return null;
    return int.tryParse(value.replaceAll(RegExp(r'[^\d]'), ''));
  }

  String? _normalizeDateTime(String? value) {
    if (value == null || value.isEmpty) return null;
    final normalized = value.replaceAll('.', '-');
    return normalized.length == 16 ? '$normalized:00' : normalized;
  }

  NovelInfo _listingToNovelInfo(Element item) {
    final link = item.querySelector(
      '.p-content__title a, .content-title .title a',
    );
    final href = link?.attributes['href'];
    if (href == null) {
      throw const FormatException('作品一覧のURLが見つかりません');
    }
    final segments = Uri.parse(href).pathSegments;
    if (segments.length != 3 ||
        segments.first != 'novel' ||
        !RegExp(r'^\d+$').hasMatch(segments[1]) ||
        !RegExp(r'^\d+$').hasMatch(segments[2])) {
      throw FormatException('アルファポリス作品URLではありません: $href');
    }
    final genreHref = item
        .querySelector('[href*="category_ids="]')
        ?.attributes['href'];
    final genreId = genreHref == null
        ? null
        : RegExp(r'category_ids=(\d+)').firstMatch(genreHref)?.group(1);
    final status = item
        .querySelectorAll('.c-attribute-tag, .content-status')
        .map((element) => element.text.trim())
        .join(' ');
    final updated = _extractDate(
      item.querySelector('.updated, .p-content__other .updated')?.text,
    );

    return NovelInfo(
      source: NovelSource.alphapolis,
      workId: buildAlphapolisWorkId(segments[1], segments[2]),
      title: link?.text.trim(),
      writer: item
          .querySelector('.p-content__author-bookinfo a, .author a')
          ?.text
          .trim(),
      story: item
          .querySelector('.p-content__abstract, .abstract .summary')
          ?.text
          .trim(),
      genreId: genreId,
      end: status.contains('完結')
          ? 0
          : status.contains('連載中')
          ? 1
          : null,
      totalCharacterCount: _parseNumber(
        item.querySelector('.wordcount, .p-content__other .wordcount')?.text,
      ),
      allPoint: _parseNumber(
        item.querySelector('.c-point--24h span, .meta .point span')?.text,
      ),
      keyword: item
          .querySelectorAll('.c-tag, .tags .tag')
          .map((element) => element.text.trim())
          .where((text) => text.isNotEmpty)
          .join(' '),
      generalLastup: _normalizeDateTime(updated),
    );
  }

  String? _extractDate(String? text) {
    if (text == null) return null;
    return RegExp(
      r'\d{4}[.-]\d{2}[.-]\d{2}(?: \d{2}:\d{2})?',
    ).firstMatch(text)?.group(0);
  }

  bool _hasNextPage(Document document, int currentPage) {
    final lastHref = document
        .querySelector('a[rel="last"]')
        ?.attributes['href'];
    if (lastHref == null) return false;
    final lastPage = int.tryParse(
      Uri.parse(lastHref).queryParameters['page'] ?? '',
    );
    return lastPage != null && currentPage < lastPage;
  }
}
