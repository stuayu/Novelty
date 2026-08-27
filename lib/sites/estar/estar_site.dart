import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:estar_parser/estar_parser.dart';
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
import 'package:novelty/utils/estar_uri.dart';
import 'package:novelty/utils/request_rate_limiter.dart';

/// エブリスタへのHTTP取得に失敗した場合の例外。
class EstarHttpException implements Exception {
  /// コンストラクタ。
  const EstarHttpException(this.statusCode, this.url);

  /// HTTPステータスコード。
  final int statusCode;

  /// リクエストURL。
  final String url;

  @override
  String toString() => 'EstarHttpException($statusCode): $url';
}

/// 公開状態でない作品を取得しようとした場合の例外。
class EstarUnavailableWorkException implements Exception {
  /// コンストラクタ。
  const EstarUnavailableWorkException(this.workId, this.status);

  /// 作品ID。
  final String workId;

  /// サイトが返した公開状態。
  final String? status;

  @override
  String toString() => 'EstarUnavailableWorkException($status): $workId';
}

/// 未確認の目次ページング範囲を超える作品だった場合の例外。
class EstarTocLimitException implements Exception {
  /// コンストラクタ。
  const EstarTocLimitException(this.workId, this.episodeCount, this.limit);

  /// 作品ID。
  final String workId;

  /// サイトが示した総話数。
  final int episodeCount;

  /// 現在の安全な取得上限。
  final int limit;

  @override
  String toString() =>
      'EstarTocLimitException($episodeCount > $limit): $workId';
}

/// 本文取得に必要な非ログインCookieが揃わない場合の例外。
class EstarGuestCookieException implements Exception {
  /// コンストラクタ。
  const EstarGuestCookieException(this.url);

  /// Cookie発行元URL。
  final String url;

  @override
  String toString() => 'EstarGuestCookieException: $url';
}

/// 有料話の本文を取得しようとした場合の例外。
class EstarPaidEpisodeException implements Exception {
  /// コンストラクタ。
  const EstarPaidEpisodeException(this.workId, this.index);

  /// 作品ID。
  final String workId;

  /// アプリ内の話数。
  final int index;

  @override
  String toString() => 'EstarPaidEpisodeException: $workId/$index';
}

/// 公開状態でない話の本文を取得しようとした場合の例外。
class EstarUnavailableEpisodeException implements Exception {
  /// コンストラクタ。
  const EstarUnavailableEpisodeException(this.workId, this.index, this.status);

  /// 作品ID。
  final String workId;

  /// アプリ内の話数。
  final int index;

  /// サイトが返した公開状態。
  final String? status;

  @override
  String toString() =>
      'EstarUnavailableEpisodeException($status): $workId/$index';
}

/// エブリスタのサイト定義。
class EstarSite implements NovelSite, RankingCacheControl {
  /// コンストラクタ。
  EstarSite({Dio? dio, RequestRateLimiter? rateLimiter})
    : _dio = _createRateLimitedDio(
        dio,
        rateLimiter ?? RequestRateLimiter(interval: const Duration(seconds: 1)),
      );

  final Dio _dio;
  final Map<String, ({Future<String> future, DateTime storedAt})> _htmlCache =
      <String, ({Future<String> future, DateTime storedAt})>{};

  static const int _maxCachedPages = 32;
  static const int _maxEpisodesWithoutConfirmedPagination = 100;
  static const int _graphqlPageBatchSize = 15;
  static const int _maxGraphqlBatches = 100;
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
  NovelSource get source => NovelSource.estar;

  @override
  List<NovelContentElement> parseEpisodeBody(String html) =>
      parseEstarEpisodeBody(html);

  @override
  String? metaText(NovelInfo info) => null;

  @override
  List<GenreMaster> get genres => const <GenreMaster>[
    GenreMaster(id: '1002', name: '青春'),
    GenreMaster(id: '1003', name: '詩・童話・絵本'),
    GenreMaster(id: '1005', name: 'ノンフィクション'),
    GenreMaster(id: '1006', name: 'ファンタジー'),
    GenreMaster(id: '1007', name: 'SF'),
    GenreMaster(id: '1008', name: 'ホラー'),
    GenreMaster(id: '1009', name: 'ミステリー'),
    GenreMaster(id: '1010', name: '歴史・時代'),
    GenreMaster(id: '1015', name: 'コメディ'),
    GenreMaster(id: '1016', name: '設定・プロット'),
    GenreMaster(id: '1018', name: 'BL'),
    GenreMaster(id: '1020', name: '恋愛'),
    GenreMaster(id: '1021', name: 'ヒューマンドラマ'),
    GenreMaster(id: '1022', name: 'エッセイ･HowTo'),
    GenreMaster(id: '1023', name: '現代ファンタジー'),
    GenreMaster(id: '1024', name: '恋愛ファンタジー'),
  ];

  @override
  List<RankingTypeMaster> get rankingTypes => const <RankingTypeMaster>[
    RankingTypeMaster(
      id: 'all',
      label: '総合',
      urlPath:
          '/novels/ranking?ranking_type=all&ranking_axis_type=general_popular',
    ),
    RankingTypeMaster(
      id: 'kiriban',
      label: 'スター',
      urlPath:
          '/novels/kiriban?ranking_type=all&ranking_axis_type=general_popular',
    ),
    RankingTypeMaster(
      id: 'new_arrivals',
      label: '新着',
      urlPath:
          '/novels/new_arrivals?ranking_type=all&ranking_axis_type=general_popular&type=pickup',
    ),
    RankingTypeMaster(
      id: 'finished',
      label: '完結',
      urlPath:
          '/novels/finished?ranking_type=all&ranking_axis_type=general_popular&type=pickup',
    ),
    RankingTypeMaster(
      id: 'trend',
      label: 'トレンド',
      urlPath: '/novels/trend?ranking_type=all&ranking_axis_type=general',
    ),
  ];

  @override
  Future<NovelInfo> fetchNovelInfo(String workId) async {
    final document = html_parser.parse(
      await _getHtml(buildEstarWorkUrl(workId)),
    );
    final data = _parseNuxtData(document);
    final status = data['status'] as String?;
    if (status != 'published') {
      throw EstarUnavailableWorkException(workId, status);
    }
    final episodeCount = _requiredPositiveInt(data, 'episodeCount');
    final title = (data['title'] as String?)?.trim();
    if (title == null || title.isEmpty) {
      throw const FormatException('エブリスタ作品のタイトルが見つかりません');
    }
    final writingStatus = data['writingStatus'] as String?;
    final modified = document
        .querySelector('time[itemprop="dateModified"]')
        ?.attributes['datetime'];

    return NovelInfo(
      source: NovelSource.estar,
      workId: workId,
      title: title,
      writer: document.querySelector('a[href^="/users/"]')?.text.trim(),
      story:
          document
              .querySelector('meta[name="description"]')
              ?.attributes['content']
              ?.trim() ??
          document.querySelector('.text')?.text.trim(),
      genreId: data['genreId']?.toString(),
      novelType: episodeCount == 1 ? 2 : 1,
      end: switch (writingStatus) {
        'finished' => 0,
        'writing' => 1,
        _ => null,
      },
      generalAllNo: episodeCount,
      totalCharacterCount: _optionalInt(data['bodyCount']),
      generalLastup: _normalizeDateTime(modified),
    );
  }

  @override
  Future<List<Episode>> fetchToc(String workId) async {
    final document = html_parser.parse(
      await _getHtml(buildEstarWorkUrl(workId)),
    );
    final data = _parseNuxtData(document);
    final episodeCount = _requiredPositiveInt(data, 'episodeCount');
    if (episodeCount > _maxEpisodesWithoutConfirmedPagination) {
      throw EstarTocLimitException(
        workId,
        episodeCount,
        _maxEpisodesWithoutConfirmedPagination,
      );
    }
    final rawEpisodes = data['episodes'];
    if (rawEpisodes is! List<dynamic> || rawEpisodes.isEmpty) {
      throw const FormatException('__NUXT_DATA__に目次がありません');
    }

    return rawEpisodes.indexed.map((entry) {
      final (offset, rawEpisode) = entry;
      if (rawEpisode is! Map<String, dynamic>) {
        throw const FormatException('エブリスタ目次の話情報がオブジェクトではありません');
      }
      final title = (rawEpisode['title'] as String?)?.trim();
      final pageNo = _optionalInt(rawEpisode['pageNo']);
      if (title == null || title.isEmpty || pageNo == null || pageNo < 1) {
        throw const FormatException('エブリスタ目次の必須項目が見つかりません');
      }
      return Episode(
        source: NovelSource.estar,
        index: offset + 1,
        subtitle: title,
        url: buildEstarEpisodeUrl(workId, pageNo),
      );
    }).toList();
  }

  @override
  Future<Episode> fetchEpisode(String workId, int index, {String? url}) async {
    if (index < 1) {
      throw ArgumentError.value(index, 'index', '1以上で指定してください');
    }
    final episodeUrl = url ?? await _resolveEpisodeUrl(workId, index);
    _assertAllowedPublicPage(Uri.parse(episodeUrl));
    if (extractEstarWorkId(episodeUrl) != workId) {
      throw FormatException('作品に属さないエピソードURLです: $episodeUrl');
    }
    final pageNo = extractEstarEpisodePageNo(episodeUrl);
    final viewerResponse = await _getResponse(episodeUrl);
    final cookie = _guestCookieHeader(viewerResponse, episodeUrl);
    final targetNodes = await _fetchEpisodeNodes(
      workId: workId,
      index: index,
      firstPageNo: pageNo,
      cookie: cookie,
      episodeUrl: episodeUrl,
    );
    if (targetNodes.isEmpty) {
      throw FormatException('エブリスタ本文に第$index話が見つかりません');
    }
    final body = targetNodes
        .map((node) => node['body'])
        .whereType<String>()
        .where((text) => text.isNotEmpty)
        .map((text) => text.replaceAll(r'\n', '\n'))
        .join('\n');
    parseEpisodeBody(body);
    final subtitle = targetNodes
        .map((node) => node['title'])
        .whereType<String>()
        .map((title) => title.trim())
        .where((title) => title.isNotEmpty)
        .firstOrNull;
    return Episode(
      source: NovelSource.estar,
      index: index,
      subtitle: subtitle,
      url: episodeUrl,
      body: body,
    );
  }

  Future<List<Map<String, dynamic>>> _fetchEpisodeNodes({
    required String workId,
    required int index,
    required int firstPageNo,
    required String cookie,
    required String episodeUrl,
  }) async {
    final collected = <int, Map<String, dynamic>>{};
    var pageNoAfter = firstPageNo;
    for (var batch = 0; batch < _maxGraphqlBatches; batch++) {
      final nodes = await _requestGraphqlNodes(
        workId: workId,
        pageNoAfter: pageNoAfter,
        cookie: cookie,
        episodeUrl: episodeUrl,
      );
      for (final node in nodes) {
        if (_optionalInt(node['episodeNo']) != index) continue;
        _validateEpisodeNode(node, workId, index);
        final pageNoInEpisode = _optionalInt(node['pageNoInEpisode']);
        if (pageNoInEpisode != null) {
          collected[pageNoInEpisode] = node;
        }
      }

      final pageCount = collected.values
          .map((node) => _optionalInt(node['pageCountInEpisode']))
          .whereType<int>()
          .firstOrNull;
      if ((pageCount != null && collected.length >= pageCount) ||
          nodes.length < _graphqlPageBatchSize) {
        final entries = collected.entries.toList()
          ..sort((left, right) => left.key.compareTo(right.key));
        return entries.map((entry) => entry.value).toList();
      }

      final lastPageNo = nodes
          .map((node) => _optionalInt(node['pageNo']))
          .whereType<int>()
          .fold<int?>(
            null,
            (max, value) => max == null || value > max ? value : max,
          );
      if (lastPageNo == null || lastPageNo < pageNoAfter) {
        throw const FormatException('エブリスタ本文APIのページングが進みません');
      }
      pageNoAfter = lastPageNo + 1;
    }
    throw const FormatException('エブリスタ本文APIの取得上限を超えました');
  }

  void _validateEpisodeNode(
    Map<String, dynamic> node,
    String workId,
    int index,
  ) {
    if (node['payRequired'] == true) {
      throw EstarPaidEpisodeException(workId, index);
    }
    final status = node['status'] as String?;
    if (status != 'published') {
      throw EstarUnavailableEpisodeException(workId, index, status);
    }
  }

  Future<List<Map<String, dynamic>>> _requestGraphqlNodes({
    required String workId,
    required int pageNoAfter,
    required String cookie,
    required String episodeUrl,
  }) async {
    final graphqlUrl = '${source.baseUrl}/api/graphql';
    final response = await _dio.post<String>(
      graphqlUrl,
      data: <String, dynamic>{
        'query': 'pages/novels/workId/viewer/nextNovelPages',
        'data': <String, dynamic>{
          'workId': workId,
          'first': _graphqlPageBatchSize,
          'pageNoAfter': pageNoAfter,
          'path': '/novels/$workId/viewer',
        },
        'fragments': <String>['novelPageInViewer'],
      },
      options: Options(
        headers: <String, String>{
          'Cookie': cookie,
          'x-from': episodeUrl,
          Headers.contentTypeHeader: Headers.jsonContentType,
          Headers.acceptHeader: Headers.jsonContentType,
        },
        responseType: ResponseType.plain,
        validateStatus: (_) => true,
      ),
    );
    if (response.statusCode != 200) {
      throw EstarHttpException(response.statusCode ?? -1, graphqlUrl);
    }
    return _parseGraphqlNodes(response.data ?? '');
  }

  @override
  Future<NovelSearchResult> searchNovels(NovelSearchQuery query) async {
    if (query.st < 1) {
      throw ArgumentError.value(query.st, 'query.st', '1以上で指定してください');
    }
    if (query.genreId case final genreIds? when genreIds.isNotEmpty) {
      throw UnsupportedError(
        'エブリスタのジャンル検索パラメータは未確認です: ${genreIds.join(',')}',
      );
    }
    final word = query.word?.trim() ?? '';
    final page = ((query.st - 1) ~/ 30) + 1;
    final uri = Uri.parse('${source.baseUrl}/novels').replace(
      queryParameters: <String, String>{
        if (word.isNotEmpty) 'keyword': word,
        if (page > 1) 'page': '$page',
      },
    );
    final data = _parseNuxtData(
      html_parser.parse(await _getHtml(uri.toString())),
    );
    final connection = _findNovelConnection(data, requireTotalCount: true);
    if (connection == null) {
      throw const FormatException('__NUXT_DATA__に検索結果がありません');
    }
    final totalCount = _optionalInt(connection['totalCount']);
    if (totalCount == null || totalCount < 0) {
      throw const FormatException('__NUXT_DATA__の検索結果件数が不正です');
    }
    final nodes = connection['nodes'] as List<dynamic>;
    if (totalCount > 0 && nodes.isEmpty) {
      throw const FormatException('__NUXT_DATA__に検索作品がありません');
    }
    return NovelSearchResult(
      novels: nodes.map(_listingToNovelInfo).toList(),
      allCount: totalCount,
    );
  }

  @override
  Future<RankingPage> fetchRanking(String rankingType, {int page = 1}) =>
      _fetchRanking(rankingType, page: page);

  @override
  Future<RankingPage> refreshRanking(String rankingType, {int page = 1}) =>
      _fetchRanking(rankingType, page: page, forceRefresh: true);

  Future<RankingPage> _fetchRanking(
    String rankingType, {
    required int page,
    bool forceRefresh = false,
  }) async {
    if (page < 1) {
      throw ArgumentError.value(page, 'page', '1以上で指定してください');
    }
    final type = rankingTypes
        .where((item) => item.id == rankingType)
        .firstOrNull;
    if (type == null) {
      throw ArgumentError.value(rankingType, 'rankingType', '未定義のランキング種別です');
    }
    final baseUri = Uri.parse(source.baseUrl).resolve(type.urlPath);
    final uri = baseUri.replace(
      queryParameters: <String, String>{
        ...baseUri.queryParameters,
        if (page > 1) 'page': '$page',
      },
    );
    if (forceRefresh) {
      _htmlCache.remove(uri.toString());
    }
    final data = _parseNuxtData(
      html_parser.parse(await _getHtml(uri.toString())),
    );
    final connection = _findNovelConnection(data);
    if (connection == null) {
      throw const FormatException('__NUXT_DATA__にランキング結果がありません');
    }
    final nodes = connection['nodes'] as List<dynamic>;
    if (nodes.isEmpty) {
      throw const FormatException('__NUXT_DATA__にランキング作品がありません');
    }
    final pageInfo = connection['pageInfo'];
    final hasNextPage = pageInfo is Map<String, dynamic>
        ? pageInfo['hasNextPage']
        : null;
    if (hasNextPage is! bool) {
      throw const FormatException('__NUXT_DATA__のランキングページ情報が不正です');
    }
    final ranked = nodes.map((node) {
      if (node is! Map<String, dynamic>) {
        throw const FormatException('エブリスタランキングの作品情報が不正です');
      }
      final rank = _optionalInt(node['rank']);
      if (rank == null || rank < 1) {
        throw const FormatException('エブリスタランキングの順位が不正です');
      }
      return (rank: rank, novel: _listingToNovelInfo(node));
    }).toList()..sort((left, right) => left.rank.compareTo(right.rank));
    return RankingPage(
      novels: ranked.map((item) => item.novel).toList(),
      hasNextPage: hasNextPage,
    );
  }

  NovelInfo _listingToNovelInfo(Object? rawNode) {
    if (rawNode is! Map<String, dynamic>) {
      throw const FormatException('エブリスタの作品情報がオブジェクトではありません');
    }
    final workId = rawNode['workId']?.toString();
    final title = (rawNode['title'] as String?)?.trim();
    if (workId == null ||
        !RegExp(r'^\d+$').hasMatch(workId) ||
        title == null ||
        title.isEmpty) {
      throw const FormatException('エブリスタ作品の必須項目が見つかりません');
    }
    final user = rawNode['user'];
    final genre = rawNode['genre'];
    final episodeCount = _optionalInt(rawNode['episodeCount']);
    final tags = rawNode['tags'];
    final tagNames = tags is List<dynamic>
        ? tags
              .map(
                (tag) => switch (tag) {
                  final String name => name,
                  final Map<String, dynamic> data => data['name'] as String?,
                  _ => null,
                },
              )
              .whereType<String>()
              .map((name) => name.trim())
              .where((name) => name.isNotEmpty)
              .toList()
        : const <String>[];
    final description = (rawNode['description'] as String?)?.trim();
    final catchphrase = (rawNode['catchphrase'] as String?)?.trim();
    return NovelInfo(
      source: NovelSource.estar,
      workId: workId,
      title: title,
      writer: user is Map<String, dynamic>
          ? (user['nickname'] as String?)?.trim()
          : null,
      story: description?.isNotEmpty == true ? description : null,
      catchphrase: catchphrase?.isNotEmpty == true ? catchphrase : null,
      genreId: genre is Map<String, dynamic>
          ? genre['genreId']?.toString()
          : null,
      novelType: switch (episodeCount) {
        1 => 2,
        final int count when count > 1 => 1,
        _ => null,
      },
      end: switch (rawNode['writingStatus']) {
        'finished' => 0,
        'writing' => 1,
        _ => null,
      },
      generalAllNo: episodeCount != null && episodeCount > 0
          ? episodeCount
          : null,
      totalCharacterCount:
          _optionalInt(rawNode['bodyCount']) ??
          _optionalInt(rawNode['publishedBodyCount']),
      keyword: tagNames.isEmpty ? null : tagNames.join(' '),
      generalLastup: _normalizeDateTime(rawNode['bodyUpdatedAt'] as String?),
    );
  }

  /// 作品一覧のconnectionを探す。
  ///
  /// `pageInfo` はconnectionと同じ階層ではなく親側に置かれるため
  /// （ランキングは `{novels: {nodes}, pageInfo}`）、探索中に直近の
  /// `pageInfo` を引き継ぎ、connectionが持たない場合はそれを補う。
  /// 空の `nodes`（未ログインの `selfUser.novels` など）は作品一覧では
  /// ないため採用しない。
  Map<String, dynamic>? _findNovelConnection(
    Object? value, {
    bool requireTotalCount = false,
    Map<String, dynamic>? inheritedPageInfo,
  }) {
    if (value is Map<String, dynamic>) {
      final ownPageInfo = value['pageInfo'];
      final pageInfo = ownPageInfo is Map<String, dynamic>
          ? ownPageInfo
          : inheritedPageInfo;

      final nodes = value['nodes'];
      final hasRequiredCount =
          !requireTotalCount || value['totalCount'] != null;
      if (nodes is List<dynamic> &&
          hasRequiredCount &&
          nodes.any(
            (node) => node is Map<String, dynamic> && node['workId'] != null,
          )) {
        return <String, dynamic>{
          ...value,
          'pageInfo': ?pageInfo,
        };
      }

      for (final child in value.values) {
        final found = _findNovelConnection(
          child,
          requireTotalCount: requireTotalCount,
          inheritedPageInfo: pageInfo,
        );
        if (found != null) return found;
      }
    } else if (value is List<dynamic>) {
      for (final child in value) {
        final found = _findNovelConnection(
          child,
          requireTotalCount: requireTotalCount,
          inheritedPageInfo: inheritedPageInfo,
        );
        if (found != null) return found;
      }
    }
    return null;
  }

  Future<String> _getHtml(String url) {
    final cached = _htmlCache[url];
    if (cached != null &&
        DateTime.now().difference(cached.storedAt) < _cacheLifetime) {
      return cached.future;
    }
    _htmlCache.remove(url);
    if (_htmlCache.length >= _maxCachedPages) {
      _htmlCache.remove(_htmlCache.keys.first);
    }
    final pending = _fetchHtml(url);
    _htmlCache[url] = (future: pending, storedAt: DateTime.now());
    return pending.catchError((Object error, StackTrace stackTrace) {
      if (_htmlCache[url]?.future == pending) {
        _htmlCache.remove(url);
      }
      Error.throwWithStackTrace(error, stackTrace);
    });
  }

  Future<String> _fetchHtml(String url) async {
    final response = await _getResponse(url);
    return response.data ?? '';
  }

  Future<Response<String>> _getResponse(String url) async {
    _assertAllowedPublicPage(Uri.parse(url));
    final response = await _dio.get<String>(
      url,
      options: Options(
        responseType: ResponseType.plain,
        validateStatus: (_) => true,
      ),
    );
    if (response.statusCode != 200) {
      throw EstarHttpException(response.statusCode ?? -1, url);
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

  String _guestCookieHeader(Response<String> response, String url) {
    final cookies = <String, String>{};
    for (final header in response.headers['set-cookie'] ?? const <String>[]) {
      final pair = header.split(';').first.trim();
      final separator = pair.indexOf('=');
      if (separator > 0) {
        cookies[pair.substring(0, separator)] = pair.substring(separator + 1);
      }
    }
    final guestinfo = cookies['guestinfo'];
    final requestorId = cookies['requestor_id'];
    if (guestinfo == null || requestorId == null) {
      throw EstarGuestCookieException(url);
    }
    return 'guestinfo=$guestinfo; requestor_id=$requestorId';
  }

  List<Map<String, dynamic>> _parseGraphqlNodes(String responseBody) {
    final jsonStart = responseBody.indexOf('{');
    if (jsonStart < 0) {
      throw const FormatException('エブリスタ本文APIのJSONが見つかりません');
    }
    final decoded = json.decode(_firstJsonObject(responseBody, jsonStart));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('エブリスタ本文APIの応答がオブジェクトではありません');
    }
    final data = decoded['data'];
    final novel = data is Map<String, dynamic> ? data['novel'] : null;
    final pages = novel is Map<String, dynamic> ? novel['pages'] : null;
    final nodes = pages is Map<String, dynamic> ? pages['nodes'] : null;
    if (nodes is! List<dynamic>) {
      throw const FormatException('エブリスタ本文APIにpages.nodesがありません');
    }
    return nodes.map((node) {
      if (node is! Map<String, dynamic>) {
        throw const FormatException('エブリスタ本文APIのページがオブジェクトではありません');
      }
      return node;
    }).toList();
  }

  String _firstJsonObject(String source, int start) {
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var index = start; index < source.length; index++) {
      final character = source[index];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (character == r'\') {
          escaped = true;
        } else if (character == '"') {
          inString = false;
        }
        continue;
      }
      if (character == '"') {
        inString = true;
      } else if (character == '{') {
        depth++;
      } else if (character == '}') {
        depth--;
        if (depth == 0) {
          return source.substring(start, index + 1);
        }
      }
    }
    throw const FormatException('エブリスタ本文APIのJSONが閉じていません');
  }

  void _assertAllowedPublicPage(Uri uri) {
    if (uri.scheme != 'https' || uri.host != 'estar.jp') {
      throw StateError('エブリスタ公式HTTPS URLではありません: $uri');
    }
    final segments = uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList();
    const listingPaths = <String>{
      '/novels',
      '/novels/ranking',
      '/novels/kiriban',
      '/novels/new_arrivals',
      '/novels/finished',
      '/novels/trend',
    };
    final isWorkPage =
        (segments.length == 2 || segments.length == 3) &&
        segments.first == 'novels' &&
        RegExp(r'^\d+$').hasMatch(segments[1]) &&
        (segments.length == 2 || segments.last == 'viewer');
    if (!listingPaths.contains(uri.path) && !isWorkPage) {
      throw StateError('確認済みのエブリスタ公開作品URLではありません: $uri');
    }
  }

  Map<String, dynamic> _parseNuxtData(Document document) {
    final script = document.querySelector('script#__NUXT_DATA__');
    if (script == null) {
      throw const FormatException('__NUXT_DATA__が見つかりません');
    }
    final decoded = json.decode(script.text);
    final normalized = decoded is List<dynamic>
        ? _decodeNuxtReferences(decoded)
        : decoded;
    if (normalized is! Map<String, dynamic>) {
      throw const FormatException('__NUXT_DATA__がオブジェクトではありません');
    }
    return normalized;
  }

  Object? _decodeNuxtReferences(List<dynamic> values) {
    if (values.isEmpty) {
      throw const FormatException('__NUXT_DATA__の参照配列が空です');
    }
    final cache = <int, Object?>{};

    Object? resolve(int index) {
      if (index < 0) {
        return switch (index) {
          -1 => null,
          -2 => double.nan,
          -3 => double.infinity,
          -4 => double.negativeInfinity,
          -5 => -0.0,
          _ => null,
        };
      }
      if (index >= values.length) {
        throw const FormatException('__NUXT_DATA__の参照先が範囲外です');
      }
      if (cache.containsKey(index)) return cache[index];
      final raw = values[index];
      if (raw is Map<String, dynamic>) {
        final result = <String, dynamic>{};
        cache[index] = result;
        for (final entry in raw.entries) {
          result[entry.key] = entry.value is int
              ? resolve(entry.value as int)
              : entry.value;
        }
        return result;
      }
      if (raw is List<dynamic>) {
        final result = <dynamic>[];
        cache[index] = result;
        result.addAll(
          raw.map((item) => item is int ? resolve(item) : item),
        );
        return _unwrapTaggedValue(result);
      }
      cache[index] = raw;
      return raw;
    }

    return _unwrapTaggedValue(resolve(0));
  }

  /// devalueのカスタムタグを剥がす。
  ///
  /// エブリスタの`__NUXT_DATA__`は値を `["ShallowReactive", {...}]` や
  /// `["ModelNovel", {...}]` のようなタグ付き2要素配列で表す。実体は後半の
  /// 要素なので、タグを取り除いて中身だけを返す。
  Object? _unwrapTaggedValue(Object? value) {
    if (value is! List<dynamic> || value.length != 2) return value;
    final tag = value.first;
    final content = value.last;
    if (tag is! String || tag.isEmpty) return value;
    if (content is! Map<String, dynamic> && content is! List<dynamic>) {
      return value;
    }
    // タグ名はNuxt標準（Reactive等）とサイト定義（Model*）の双方があるため、
    // 名前を列挙せず「先頭が識別子、後半が構造体」の形だけで判定する。
    if (!RegExp(r'^[A-Z][A-Za-z0-9_]*$').hasMatch(tag)) return value;
    return content;
  }

  int _requiredPositiveInt(Map<String, dynamic> data, String key) {
    final value = _optionalInt(data[key]);
    if (value == null || value < 1) {
      throw FormatException('__NUXT_DATA__の$keyが正の整数ではありません');
    }
    return value;
  }

  int? _optionalInt(Object? value) {
    return switch (value) {
      final int number => number,
      final String text => int.tryParse(text),
      _ => null,
    };
  }

  String? _normalizeDateTime(String? value) {
    if (value == null || value.isEmpty) return null;
    final match = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})',
    ).firstMatch(value);
    if (match == null) return null;
    return '${match.group(1)}-${match.group(2)}-${match.group(3)} '
        '${match.group(4)}:${match.group(5)}:${match.group(6)}';
  }
}
