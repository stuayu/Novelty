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
class EstarSite implements NovelSite {
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
  List<RankingTypeMaster> get rankingTypes => const <RankingTypeMaster>[];

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
  Future<NovelSearchResult> searchNovels(NovelSearchQuery query) {
    throw UnsupportedError('エブリスタの検索は未対応です');
  }

  @override
  Future<RankingPage> fetchRanking(String rankingType, {int page = 1}) {
    throw UnsupportedError('エブリスタのランキングは未対応です');
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
    if ((segments.length != 2 && segments.length != 3) ||
        segments.first != 'novels' ||
        !RegExp(r'^\d+$').hasMatch(segments[1]) ||
        (segments.length == 3 && segments.last != 'viewer')) {
      throw StateError('確認済みのエブリスタ公開作品URLではありません: $uri');
    }
  }

  Map<String, dynamic> _parseNuxtData(Document document) {
    final script = document.querySelector('script#__NUXT_DATA__');
    if (script == null) {
      throw const FormatException('__NUXT_DATA__が見つかりません');
    }
    final decoded = json.decode(script.text);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('__NUXT_DATA__がオブジェクトではありません');
    }
    return decoded;
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
