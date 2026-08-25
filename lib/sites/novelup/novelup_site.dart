import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:novelty/models/episode.dart';
import 'package:novelty/models/novel_info.dart';
import 'package:novelty/models/novel_search_query.dart';
import 'package:novelty/models/novel_search_result.dart';
import 'package:novelty/models/ranking_page.dart';
import 'package:novelty/services/api_service.dart' show NovelNotFoundException;
import 'package:novelty/services/http_client.dart';
import 'package:novelty/sites/novel_site.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:novelty/utils/novelup_uri.dart';
import 'package:novelty/utils/request_rate_limiter.dart';
import 'package:novelup_parser/novelup_parser.dart';

/// ノベルアップ＋へのHTTP取得に失敗した場合の例外。
class NovelupHttpException implements Exception {
  /// コンストラクタ。
  const NovelupHttpException(this.statusCode, this.url);

  /// HTTPステータスコード。
  final int statusCode;

  /// リクエストURL。
  final String url;

  @override
  String toString() => 'NovelupHttpException($statusCode): $url';
}

/// 削除済みまたは存在しない作品を取得した場合の例外。
class NovelupWorkNotFoundException implements NovelNotFoundException {
  /// コンストラクタ。
  const NovelupWorkNotFoundException(this.url);

  /// 判定対象URL。
  final String url;

  @override
  String toString() => 'NovelupWorkNotFoundException: $url';
}

/// ノベルアップ＋のサイト定義。
class NovelupSite implements NovelSite {
  /// コンストラクタ。
  NovelupSite({Dio? dio, RequestRateLimiter? rateLimiter})
    : _dio = _createRateLimitedDio(
        dio,
        rateLimiter ?? RequestRateLimiter(interval: const Duration(seconds: 2)),
      );

  // ノベルアップ＋は研究用User-AgentをCloudFrontで拒否する。
  // 通常取得ではcreateNoveltyDioのプラットフォーム別ブラウザUAを利用する。
  final Dio _dio;
  final Map<String, ({Future<String> future, DateTime storedAt})> _htmlCache =
      <String, ({Future<String> future, DateTime storedAt})>{};

  static const int _maxCachedPages = 32;
  static const Duration _cacheLifetime = Duration(minutes: 10);

  static Dio _createRateLimitedDio(
    Dio? dio,
    RequestRateLimiter rateLimiter,
  ) {
    return dio == null
        ? createNoveltyDio(rateLimiter: rateLimiter)
        : attachNoveltyRateLimiter(dio, rateLimiter);
  }

  @override
  NovelSource get source => NovelSource.novelup;

  @override
  List<NovelContentElement> parseEpisodeBody(String html) =>
      parseNovelupEpisodeBody(html);

  @override
  String? metaText(NovelInfo info) => null;

  @override
  List<GenreMaster> get genres => const <GenreMaster>[
    GenreMaster(id: '1', name: '異世界ファンタジー'),
    GenreMaster(id: '2', name: '現代/その他ファンタジー'),
    GenreMaster(id: '3', name: 'SF'),
    GenreMaster(id: '4', name: '恋愛/ラブコメ'),
    GenreMaster(id: '5', name: 'ホラー'),
    GenreMaster(id: '6', name: 'ミステリー'),
    GenreMaster(id: '7', name: 'エッセイ/評論/コラム'),
    GenreMaster(id: '8', name: '歴史/時代'),
    GenreMaster(id: '9', name: '文芸/純文学'),
    GenreMaster(id: '10', name: 'ブログ/活動報告'),
    GenreMaster(id: '11', name: '現代/青春ドラマ'),
    GenreMaster(id: '12', name: '詩/短歌'),
    GenreMaster(id: '13', name: 'ノベプラ掲載作品紹介'),
    GenreMaster(id: '14', name: 'コメディ/ギャグ'),
    GenreMaster(id: '52', name: '二次創作'),
    GenreMaster(id: '99', name: '童話/絵本/その他'),
  ];

  @override
  List<RankingTypeMaster> get rankingTypes => const <RankingTypeMaster>[
    RankingTypeMaster(id: 'all', label: '総合', urlPath: '/ranking/all/day'),
    RankingTypeMaster(
      id: 'high-fantasy',
      label: '異世界ファンタジー',
      urlPath: '/ranking/high-fantasy/day',
    ),
    RankingTypeMaster(
      id: 'low-fantasy',
      label: '現代/その他ファンタジー',
      urlPath: '/ranking/low-fantasy/day',
    ),
    RankingTypeMaster(id: 'sf', label: 'SF', urlPath: '/ranking/sf/day'),
    RankingTypeMaster(
      id: 'romance',
      label: '恋愛/ラブコメ',
      urlPath: '/ranking/romance/day',
    ),
    RankingTypeMaster(
      id: 'horror',
      label: 'ホラー',
      urlPath: '/ranking/horror/day',
    ),
    RankingTypeMaster(
      id: 'mystery',
      label: 'ミステリー',
      urlPath: '/ranking/mystery/day',
    ),
    RankingTypeMaster(
      id: 'essay',
      label: 'エッセイ/評論/コラム',
      urlPath: '/ranking/essay/day',
    ),
    RankingTypeMaster(
      id: 'history',
      label: '歴史/時代',
      urlPath: '/ranking/history/day',
    ),
    RankingTypeMaster(
      id: 'literature',
      label: '文芸/純文学',
      urlPath: '/ranking/literature/day',
    ),
    RankingTypeMaster(
      id: 'blog',
      label: 'ブログ/活動報告',
      urlPath: '/ranking/blog/day',
    ),
    RankingTypeMaster(
      id: 'drama',
      label: '現代/青春ドラマ',
      urlPath: '/ranking/drama/day',
    ),
    RankingTypeMaster(
      id: 'poem',
      label: '詩/短歌',
      urlPath: '/ranking/poem/day',
    ),
    RankingTypeMaster(
      id: 'introduction',
      label: 'ノベプラ掲載作品紹介',
      urlPath: '/ranking/introduction/day',
    ),
    RankingTypeMaster(
      id: 'comedy',
      label: 'コメディ/ギャグ',
      urlPath: '/ranking/comedy/day',
    ),
    RankingTypeMaster(
      id: 'license',
      label: '二次創作',
      urlPath: '/ranking/license/day',
    ),
    RankingTypeMaster(
      id: 'others',
      label: '童話/絵本/その他',
      urlPath: '/ranking/others/day',
    ),
    RankingTypeMaster(
      id: 'nuponly',
      label: 'ノベプラオンリー',
      urlPath: '/ranking/nuponly/day',
    ),
    RankingTypeMaster(
      id: 'short',
      label: '短編小説',
      urlPath: '/ranking/short/day',
    ),
    RankingTypeMaster(
      id: 'shorts',
      label: '短編小説集',
      urlPath: '/ranking/shorts/day',
    ),
    RankingTypeMaster(
      id: 'finished',
      label: '完結作品',
      urlPath: '/ranking/finished/day',
    ),
  ];

  @override
  Future<NovelInfo> fetchNovelInfo(String workId) async {
    final document = html_parser.parse(
      await _fetchHtml(buildNovelupWorkUrl(workId)),
    );
    final jsonLd = _creativeWorkJsonLd(document);
    final title =
        document.querySelector('.storyTitle, .story_name')?.text.trim() ??
        (jsonLd['name'] as String?)?.trim();
    final authorLink = document.querySelector(
      '.storyAuthor[href], .story_author_name a[href]',
    );
    final author = jsonLd['author'];
    final writer =
        authorLink?.text.trim() ??
        (author is Map<String, dynamic>
            ? (author['name'] as String?)?.trim()
            : null);
    if (title == null || title.isEmpty || writer == null || writer.isEmpty) {
      throw const FormatException('ノベルアップ＋作品情報の必須項目が見つかりません');
    }
    final episodeCount = _parseNumber(
      document.querySelector('.totalEpisode, .total_episode_num')?.text ??
          document.querySelector('.story_episode_count')?.text,
    );
    if (episodeCount == null || episodeCount < 1) {
      throw const FormatException('ノベルアップ＋作品の総話数が見つかりません');
    }
    final typeText = document.querySelector('.story_short')?.text.trim();
    final isShort = typeText == '短編' || episodeCount == 1;
    final status = (jsonLd['creativeWorkStatus'] as String?)?.trim();
    final genreName =
        document.querySelector('.story_genre')?.text.trim() ??
        (jsonLd['genre'] as String?)?.trim();

    return NovelInfo(
      source: NovelSource.novelup,
      workId: workId,
      title: title,
      writer: writer,
      userId: _userIdFromUrl(
        authorLink?.attributes['href'] ??
            (author is Map<String, dynamic> ? author['url'] as String? : null),
      ),
      story:
          document.querySelector('.novel_synopsis p')?.text.trim() ??
          (jsonLd['description'] as String?)?.trim(),
      genreId: _genreIdForName(genreName),
      // なろうの意味論: 1=連載、2=短編、endは0=短編・完結、1=連載中。
      novelType: isShort ? 2 : 1,
      end: isShort
          ? 0
          : status == '連載中'
          ? 1
          : status?.contains('完結') == true
          ? 0
          : null,
      generalAllNo: episodeCount,
      totalCharacterCount: _parseNumber(
        document.querySelector('.story_length')?.text,
      ),
      generalFirstup: _normalizeDate(jsonLd['datePublished'] as String?),
      generalLastup: _normalizeJapaneseDate(
        document.querySelector('.story_update')?.text,
      ),
    );
  }

  @override
  Future<List<Episode>> fetchToc(String workId) async {
    final workUrl = buildNovelupWorkUrl(workId);
    final firstDocument = html_parser.parse(await _fetchHtml(workUrl));
    final lastPage = _lastTocPage(firstDocument, workId);
    if (lastPage > 100) {
      throw const FormatException('ノベルアップ＋目次のページ数が取得上限を超えています');
    }

    final episodes = <Episode>[];
    _appendTocPage(firstDocument, workId, episodes);
    for (var page = 2; page <= lastPage; page++) {
      final pageUrl = Uri.parse(
        workUrl,
      ).replace(queryParameters: <String, String>{'p': '$page'}).toString();
      final document = html_parser.parse(await _fetchHtml(pageUrl));
      _appendTocPage(document, workId, episodes);
    }
    if (episodes.isEmpty) {
      throw const FormatException('ノベルアップ＋作品の目次が見つかりません');
    }
    return episodes;
  }

  @override
  Future<Episode> fetchEpisode(String workId, int index, {String? url}) async {
    if (index < 1) {
      throw ArgumentError.value(index, 'index', '1以上で指定してください');
    }
    final episodeUrl = url ?? await _resolveEpisodeUrl(workId, index);
    final uri = Uri.parse(episodeUrl);
    _assertAllowed(uri);
    if (extractNovelupWorkId(episodeUrl) != workId) {
      throw FormatException('作品に属さないエピソードURLです: $episodeUrl');
    }
    extractNovelupEpisodeId(episodeUrl);
    final html = await _fetchHtml(episodeUrl);
    // 空本文やエラーページを成功扱いしない。
    parseEpisodeBody(html);
    final document = html_parser.parse(html);
    final subtitle = document.querySelector('.episode_title h1')?.text.trim();
    if (subtitle == null || subtitle.isEmpty) {
      throw const FormatException('ノベルアップ＋本文の話タイトルが見つかりません');
    }
    return Episode(
      source: NovelSource.novelup,
      index: index,
      subtitle: subtitle,
      url: episodeUrl,
      body: html,
    );
  }

  @override
  Future<NovelSearchResult> searchNovels(NovelSearchQuery query) async {
    final word = query.word?.trim() ?? '';
    final page = ((query.st - 1) ~/ 30) + 1;
    final parameters = <String, String>{
      if (word.isNotEmpty) 'q': word,
      // NovelSearchQueryの既定newは、実測済みの更新順（エピソード）へ対応する。
      'sort': '1',
      for (final genreId in query.genreId ?? const <String>[])
        'genre[$genreId]': '1',
      if (page > 1) 'p': '$page',
    };
    final uri = Uri.parse(
      '${source.baseUrl}/search',
    ).replace(queryParameters: parameters);
    final document = html_parser.parse(await _fetchHtml(uri.toString()));
    final countText = document.querySelector('.searchCount')?.text;
    final allCount = _parseNumber(countText);
    if (allCount == null) {
      throw const FormatException('ノベルアップ＋検索結果件数が見つかりません');
    }
    final items = document.querySelectorAll(
      '.searchResultList > li, .story_card',
    );
    if (allCount > 0 && items.isEmpty) {
      throw const FormatException('ノベルアップ＋検索結果の作品DOMが見つかりません');
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
    final type = rankingTypes
        .where((item) => item.id == rankingType)
        .firstOrNull;
    if (type == null) {
      throw ArgumentError.value(rankingType, 'rankingType', '未定義のランキング種別です');
    }
    final uri = Uri.parse(source.baseUrl)
        .resolve(type.urlPath)
        .replace(
          queryParameters: page > 1 ? <String, String>{'p': '$page'} : null,
        );
    final document = html_parser.parse(await _fetchHtml(uri.toString()));
    final items = document.querySelectorAll('.one_set.ranking');
    if (items.isEmpty) {
      throw const FormatException('ノベルアップ＋ランキングの作品DOMが見つかりません');
    }
    return RankingPage(
      novels: items.map(_listingToNovelInfo).toList(),
      hasNextPage: _hasNextPage(document, uri.path, page),
    );
  }

  Future<String> _fetchHtml(String url) {
    final cached = _htmlCache[url];
    if (cached != null &&
        DateTime.now().difference(cached.storedAt) < _cacheLifetime) {
      return cached.future;
    }
    _htmlCache.remove(url);
    if (_htmlCache.length >= _maxCachedPages) {
      _htmlCache.remove(_htmlCache.keys.first);
    }
    final pending = _requestHtml(url);
    _htmlCache[url] = (future: pending, storedAt: DateTime.now());
    return pending.catchError((Object error, StackTrace stackTrace) {
      if (_htmlCache[url]?.future == pending) {
        _htmlCache.remove(url);
      }
      Error.throwWithStackTrace(error, stackTrace);
    });
  }

  Future<String> _requestHtml(String url) async {
    final uri = Uri.parse(url);
    _assertAllowed(uri);
    final response = await _dio.get<String>(
      url,
      options: Options(
        responseType: ResponseType.plain,
        validateStatus: (_) => true,
      ),
    );
    if (response.statusCode == 404) {
      throw NovelupWorkNotFoundException(url);
    }
    if (response.statusCode != 200) {
      throw NovelupHttpException(response.statusCode ?? -1, url);
    }
    return response.data ?? '';
  }

  void _assertAllowed(Uri uri) {
    if (uri.scheme != 'https' || uri.host != 'novelup.plus') {
      throw StateError('ノベルアップ＋公式HTTPS URLではありません: $uri');
    }
    if (uri.path == '/api' || uri.path.startsWith('/api/')) {
      throw StateError('robots.txtにより取得が禁止されています: $uri');
    }
  }

  Map<String, dynamic> _creativeWorkJsonLd(Document document) {
    for (final script in document.querySelectorAll(
      'script[type="application/ld+json"]',
    )) {
      final decoded = json.decode(script.text);
      if (decoded is Map<String, dynamic> &&
          decoded['@type'] == 'CreativeWork') {
        return decoded;
      }
    }
    throw const FormatException('ノベルアップ＋作品のJSON-LDが見つかりません');
  }

  String? _genreIdForName(String? name) {
    if (name == null || name.isEmpty) return null;
    return genres.where((genre) => genre.name == name).firstOrNull?.id;
  }

  int? _userIdFromUrl(String? url) {
    if (url == null) return null;
    return int.tryParse(
      RegExp(r'/user/(\d+)/profile').firstMatch(url)?.group(1) ?? '',
    );
  }

  int? _parseNumber(String? value) {
    if (value == null) return null;
    return int.tryParse(value.replaceAll(RegExp(r'[^\d]'), ''));
  }

  int _lastTocPage(Document document, String workId) {
    var lastPage = 1;
    for (final link in document.querySelectorAll('a[href]')) {
      final href = link.attributes['href'];
      if (href == null) continue;
      final uri = Uri.parse(source.baseUrl).resolve(href);
      if (uri.host != 'novelup.plus') continue;
      try {
        if (extractNovelupWorkId(uri.toString()) != workId) continue;
      } on FormatException {
        continue;
      }
      final page = int.tryParse(uri.queryParameters['p'] ?? '');
      if (page != null && page > lastPage) {
        lastPage = page;
      }
    }
    return lastPage;
  }

  Future<String> _resolveEpisodeUrl(String workId, int index) async {
    final episodes = await fetchToc(workId);
    final episode = episodes.where((item) => item.index == index).firstOrNull;
    if (episode?.url == null) {
      throw StateError('エピソード $index が見つかりません: $workId');
    }
    return episode!.url!;
  }

  void _appendTocPage(
    Document document,
    String workId,
    List<Episode> episodes,
  ) {
    final links = document.querySelectorAll(
      '.episodeListItem .episodeTitle[href]',
    );
    if (links.isEmpty) {
      throw const FormatException('ノベルアップ＋目次の作品DOMが見つかりません');
    }
    for (final link in links) {
      final href = link.attributes['href'];
      final title = link.text.trim();
      if (href == null || title.isEmpty) {
        throw const FormatException('ノベルアップ＋目次の必須項目が見つかりません');
      }
      final episodeUrl = Uri.parse(source.baseUrl).resolve(href).toString();
      if (extractNovelupWorkId(episodeUrl) != workId) {
        throw FormatException('作品に属さないエピソードURLです: $episodeUrl');
      }
      // サイト固有IDはURLへ保持し、indexは目次順の1始まり連番にする。
      episodes.add(
        Episode(
          source: NovelSource.novelup,
          index: episodes.length + 1,
          subtitle: title,
          url: episodeUrl,
          update: link.parent?.querySelector('.publishDate')?.text.trim(),
        ),
      );
    }
  }

  String? _normalizeDate(String? value) {
    if (value == null || value.isEmpty) return null;
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(value);
    if (match == null) return null;
    return '${match.group(1)}-${match.group(2)}-${match.group(3)} 00:00:00';
  }

  String? _normalizeJapaneseDate(String? value) {
    if (value == null) return null;
    final match = RegExp(r'(\d{4})年(\d{1,2})月(\d{1,2})日').firstMatch(value);
    if (match == null) return null;
    final month = match.group(2)!.padLeft(2, '0');
    final day = match.group(3)!.padLeft(2, '0');
    return '${match.group(1)}-$month-$day 00:00:00';
  }

  NovelInfo _listingToNovelInfo(Element item) {
    final link = item.querySelector('.story_name a[href]');
    final href = link?.attributes['href'];
    if (href == null) {
      throw const FormatException('ノベルアップ＋作品一覧のURLが見つかりません');
    }
    final workUrl = Uri.parse(source.baseUrl).resolve(href).toString();
    final workId = extractNovelupWorkId(workUrl);
    final typeText = item.querySelector('.story_short')?.text.trim();
    final episodeCount = _parseNumber(
      item.querySelector('.story_episode_count')?.text,
    );
    final isShort = typeText == '短編' || episodeCount == 1;
    final genreName = item.querySelector('.story_genre')?.text.trim();
    final authorLink = item.querySelector('.story_author_name a[href]');
    final statusText = item.text;

    return NovelInfo(
      source: NovelSource.novelup,
      workId: workId,
      title: link?.text.trim(),
      writer:
          authorLink?.text.trim() ??
          item.querySelector('.story_author_name')?.text.trim(),
      userId: _userIdFromUrl(authorLink?.attributes['href']),
      story: item.querySelector('.story_introduction')?.text.trim(),
      genreId: _genreIdForName(genreName),
      novelType: isShort ? 2 : 1,
      end: isShort
          ? 0
          : statusText.contains('完結')
          ? 0
          : null,
      generalAllNo: episodeCount,
      totalCharacterCount: _parseNumber(
        item.querySelector('.story_length')?.text,
      ),
      generalLastup: _normalizeJapaneseDate(
        item.querySelector('.story_update')?.text,
      ),
    );
  }

  bool _hasNextPage(Document document, String path, int currentPage) {
    for (final link in document.querySelectorAll('a[href]')) {
      final href = link.attributes['href'];
      if (href == null) continue;
      final uri = Uri.parse(source.baseUrl).resolve(href);
      final page = int.tryParse(uri.queryParameters['p'] ?? '');
      if (uri.host == 'novelup.plus' &&
          uri.path == path &&
          page != null &&
          page > currentPage) {
        return true;
      }
    }
    return false;
  }
}
