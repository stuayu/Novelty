import 'package:dio/dio.dart';
import 'package:hameln_parser/hameln_parser.dart';
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
import 'package:novelty/utils/hameln_uri.dart';
import 'package:novelty/utils/request_rate_limiter.dart';

/// ハーメルンへのHTTP取得に失敗した場合の例外。
class HamelnHttpException implements Exception {
  /// コンストラクタ。
  const HamelnHttpException(this.statusCode, this.url);

  /// HTTPステータスコード。
  final int statusCode;

  /// リクエストURL。
  final String url;

  @override
  String toString() => 'HamelnHttpException($statusCode): $url';
}

/// 削除済み作品または誤った作品URLだった場合の例外。
class HamelnWorkNotFoundException implements NovelNotFoundException {
  /// コンストラクタ。
  const HamelnWorkNotFoundException(this.url);

  /// 判定対象URL。
  final String url;

  @override
  String toString() => 'HamelnWorkNotFoundException: $url';
}

/// R18年齢確認ページのため本文を取得できない場合の例外。
class HamelnAgeConfirmationException implements Exception {
  /// コンストラクタ。
  const HamelnAgeConfirmationException(this.url);

  /// 判定対象URL。
  final String url;

  @override
  String toString() => 'HamelnAgeConfirmationException: $url';
}

/// CloudflareのJavaScriptチャレンジによりHTMLを取得できない場合の例外。
class HamelnCloudflareChallengeException implements Exception {
  /// コンストラクタ。
  const HamelnCloudflareChallengeException(this.url);

  /// 判定対象URL。
  final String url;

  @override
  String toString() => 'HamelnCloudflareChallengeException: $url';
}

/// ハーメルンのサイト定義。
class HamelnSite implements NovelSite {
  /// コンストラクタ。
  HamelnSite({Dio? dio, RequestRateLimiter? rateLimiter})
    : _dio = _createRateLimitedDio(
        dio,
        rateLimiter ?? RequestRateLimiter(interval: const Duration(seconds: 3)),
      );

  final Dio _dio;
  final Map<String, ({Future<String> future, DateTime storedAt})> _htmlCache =
      <String, ({Future<String> future, DateTime storedAt})>{};

  static const int _maxCachedPages = 32;
  static const int _maxEpisodesPerWork = 500;
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
  NovelSource get source => NovelSource.hameln;

  @override
  List<NovelContentElement> parseEpisodeBody(String html) =>
      parseHamelnEpisodeBody(html);

  @override
  String? metaText(NovelInfo info) {
    final point = info.allPoint;
    return point == null ? null : '評価 $point';
  }

  @override
  List<GenreMaster> get genres {
    // 固定IDのジャンル体系が存在しないため、検索語を推測でマスタ化しない。
    return const <GenreMaster>[];
  }

  @override
  List<RankingTypeMaster> get rankingTypes => const <RankingTypeMaster>[
    RankingTypeMaster(
      id: 'rank_day',
      label: '一般総合・日間',
      urlPath: '/?mode=rank_day',
    ),
    RankingTypeMaster(
      id: 'rank_2_day',
      label: '一般二次・日間',
      urlPath: '/?mode=rank_2_day',
    ),
    RankingTypeMaster(
      id: 'rank_ori_day',
      label: '一般オリ・日間',
      urlPath: '/?mode=rank_ori_day',
    ),
    RankingTypeMaster(
      id: 'rank_ss_day',
      label: '一般短編・日間',
      urlPath: '/?mode=rank_ss_day',
    ),
    RankingTypeMaster(
      id: 'rank_week',
      label: '週間',
      urlPath: '/?mode=rank_week',
    ),
    RankingTypeMaster(
      id: 'rank_month',
      label: '月間',
      urlPath: '/?mode=rank_month',
    ),
    RankingTypeMaster(
      id: 'rank_3month',
      label: '四半期',
      urlPath: '/?mode=rank_3month',
    ),
    RankingTypeMaster(
      id: 'rank_year',
      label: '年間',
      urlPath: '/?mode=rank_year',
    ),
    RankingTypeMaster(
      id: 'rank_total',
      label: '累計',
      urlPath: '/?mode=rank_total',
    ),
    RankingTypeMaster(
      id: 'rank_relative',
      label: '相対',
      urlPath: '/?mode=rank_relative',
    ),
    RankingTypeMaster(
      id: 'rank_complete_total',
      label: '完結累計',
      urlPath: '/?mode=rank_complete_total',
    ),
    RankingTypeMaster(
      id: 'rank_complete_relative',
      label: '完結相対',
      urlPath: '/?mode=rank_complete_relative',
    ),
    RankingTypeMaster(id: 'rank_wsi', label: 'WSI', urlPath: '/?mode=rank_wsi'),
    RankingTypeMaster(
      id: 'rank_favo_ratio_nocolor',
      label: 'お気に入り率',
      urlPath: '/?mode=rank_favo_ratio_nocolor',
    ),
    RankingTypeMaster(
      id: 'rank_add_day2',
      label: '透明',
      urlPath: '/?mode=rank_add_day2',
    ),
    RankingTypeMaster(
      id: 'rank_new_user',
      label: 'ルーキー',
      urlPath: '/?mode=rank_new_user',
    ),
    RankingTypeMaster(id: 'rank_new', label: '新作', urlPath: '/?mode=rank_new'),
    RankingTypeMaster(
      id: 'rank_add_day',
      label: '日間加点',
      urlPath: '/?mode=rank_add_day',
    ),
  ];

  @override
  Future<NovelInfo> fetchNovelInfo(String workId) async {
    final document = html_parser.parse(
      await _getHtml(buildHamelnWorkUrl(workId)),
    );
    final isShort = document.querySelector('#honbun') != null;
    final title = isShort
        ? document.querySelector('.ss span[style*="font-size:120%"] a')
        : document.querySelector('#maind span[itemprop="name"]');
    final author = isShort
        ? _shortAuthor(document.querySelector('.ss p')?.text)
        : document
              .querySelector('#maind span[itemprop="author"] a')
              ?.text
              .trim();
    if (title == null || author == null || author.isEmpty) {
      throw const FormatException('ハーメルン作品情報の必須項目が見つかりません');
    }
    final episodeCount = isShort
        ? 1
        : document.querySelectorAll('.episode-list__item').length;
    if (episodeCount == 0) {
      throw const FormatException('ハーメルン作品のエピソードが見つかりません');
    }
    final story = !isShort
        ? document
              .querySelectorAll('#maind > .ss')
              .where(
                (element) => element.querySelector('[itemprop="name"]') == null,
              )
              .firstOrNull
              ?.text
              .trim()
        : null;

    return NovelInfo(
      source: NovelSource.hameln,
      workId: workId,
      title: title.text.trim(),
      writer: author,
      story: story,
      novelType: isShort ? 2 : 1,
      end: isShort ? 0 : null,
      generalAllNo: episodeCount,
      keyword: document
          .querySelectorAll('span[itemprop="keywords"] a')
          .map((element) => element.text.trim())
          .where((text) => text.isNotEmpty)
          .join(' '),
    );
  }

  @override
  Future<List<Episode>> fetchToc(String workId) async {
    final workUrl = buildHamelnWorkUrl(workId);
    final document = html_parser.parse(await _getHtml(workUrl));
    if (document.querySelector('#honbun') != null) {
      final subtitle = document
          .querySelector('#maind > span[style*="font-size:120%"]')
          ?.text
          .trim();
      if (subtitle == null || subtitle.isEmpty) {
        throw const FormatException('ハーメルン短編の話タイトルが見つかりません');
      }
      return <Episode>[
        Episode(
          source: NovelSource.hameln,
          index: 1,
          subtitle: subtitle,
          url: workUrl,
        ),
      ];
    }
    final links = document.querySelectorAll(
      '.episode-list__item > .episode-list__link',
    );
    if (links.isEmpty) {
      throw const FormatException('ハーメルン作品の目次が見つかりません');
    }
    if (links.length > _maxEpisodesPerWork) {
      throw const FormatException('ハーメルン作品の目次が取得上限500話を超えています');
    }

    return links.indexed.map((entry) {
      final (offset, link) = entry;
      final href = link.attributes['href'];
      final title = link.querySelector('.episode-list__title')?.text.trim();
      if (href == null || title == null || title.isEmpty) {
        throw const FormatException('ハーメルン目次の必須項目が見つかりません');
      }
      final episodeUrl = Uri.parse(workUrl).resolve(href).toString();
      if (extractHamelnWorkId(episodeUrl) != workId) {
        throw FormatException('作品に属さないエピソードURLです: $episodeUrl');
      }
      final revised = link
          .querySelector('.episode-list__revision[title]')
          ?.attributes['title']
          ?.replaceFirst(RegExp(r'改稿$'), '')
          .trim();
      return Episode(
        source: NovelSource.hameln,
        index: offset + 1,
        subtitle: title,
        url: episodeUrl,
        update: link.querySelector('.episode-list__date')?.text.trim(),
        revised: revised,
      );
    }).toList();
  }

  @override
  Future<Episode> fetchEpisode(String workId, int index, {String? url}) async {
    final episodeUrl = url ?? await _resolveEpisodeUrl(workId, index);
    final uri = Uri.parse(episodeUrl);
    _assertAllowed(uri);
    if (extractHamelnWorkId(episodeUrl) != workId) {
      throw FormatException('作品に属さないエピソードURLです: $episodeUrl');
    }
    final html = await _getHtml(episodeUrl);
    parseEpisodeBody(html);
    final document = html_parser.parse(html);
    final subtitle =
        (document.querySelector('#maind > span[style*="font-size:120%"]') ??
                document.querySelector('span[style*="font-size:120%"]'))
            ?.text
            .trim();
    return Episode(
      source: NovelSource.hameln,
      index: index,
      subtitle: subtitle,
      url: episodeUrl,
      body: html,
    );
  }

  @override
  Future<NovelSearchResult> searchNovels(NovelSearchQuery query) {
    throw UnsupportedError('ハーメルンの検索は未対応です');
  }

  @override
  Future<RankingPage> fetchRanking(String rankingType, {int page = 1}) async {
    if (page < 1) {
      throw ArgumentError.value(page, 'page', '1以上で指定してください');
    }
    final type = rankingTypes
        .where((type) => type.id == rankingType)
        .firstOrNull;
    if (type == null) {
      throw ArgumentError.value(rankingType, 'rankingType', '未定義のランキング種別です');
    }
    if (page > 1) {
      // ページングURLが未確認のため、推測したリクエストは送らず終端する。
      return const RankingPage(novels: <NovelInfo>[], hasNextPage: false);
    }
    final url = Uri.parse(source.baseUrl).resolve(type.urlPath).toString();
    final document = html_parser.parse(await _getHtml(url));
    final items = document.querySelectorAll('div.section3[id^="nid_"]');
    if (items.isEmpty) {
      throw const FormatException('ハーメルンランキングの作品DOMが見つかりません');
    }
    return RankingPage(
      novels: items.map(_rankingItemToNovelInfo).toList(),
      // 実取得ページにページャーが無いため、次ページありとは判定しない。
      hasNextPage: false,
    );
  }

  NovelInfo _rankingItemToNovelInfo(Element item) {
    final link = item.querySelector('.blo_title_base > a[href*="/novel/"]');
    final href = link?.attributes['href'];
    if (href == null) {
      throw const FormatException('ハーメルンランキングの作品URLが見つかりません');
    }
    final workId = extractHamelnWorkId(href);
    final status = item.querySelector('.blo_wasuu_base span[title]');
    final statusTitle = status?.attributes['title'] ?? '';
    final isShort = statusTitle == '短編';
    final isCompleted = statusTitle == '連載(完結)';
    final episodeCount = isShort
        ? 1
        : _parseNumber(
            item.querySelector('.blo_wasuu_base a[title="最新話へのリンク"]')?.text,
          );
    final metrics = item
        .querySelectorAll('.all_keyword')
        .map((element) => element.text.trim())
        .firstWhere(
          (text) => text.contains('評価：'),
          orElse: () => '',
        );
    final genreAndKeywords = <String>[
      item.querySelector('.blo_genre')?.text.trim() ?? '',
      ...item
          .querySelectorAll('.all_keyword')
          .map((element) => element.text.trim())
          .where((text) => text.isNotEmpty && !text.contains('評価：')),
    ].where((text) => text.isNotEmpty).join(' ');

    return NovelInfo(
      source: NovelSource.hameln,
      workId: workId,
      title: link?.text.trim(),
      writer:
          item.querySelector('.blo_title_sak a')?.text.trim() ??
          item
              .querySelector('.blo_title_sak')
              ?.text
              .replaceFirst(RegExp(r'^\s*作：\s*'), '')
              .trim(),
      story: item.querySelector('.all_arasuji .blo_inword')?.text.trim(),
      // なろうの意味論: 1=連載、2=短編、endは0=短編・完結、1=連載中。
      novelType: isShort ? 2 : 1,
      end: isShort || isCompleted ? 0 : 1,
      generalAllNo: episodeCount,
      totalCharacterCount: _parseNumber(
        item.querySelector('.blo_wasuu_base [title="総文字数"]')?.text,
      ),
      keyword: genreAndKeywords,
      generalLastup: _rankingLastUpdated(item),
      allPoint: _metricNumber(metrics, '評価'),
      favNovelCnt: _metricNumber(metrics, 'お気に入り'),
      impressionCnt: _metricNumber(metrics, '感想'),
      allHyokaCnt: _metricNumber(metrics, '投票者'),
      isr15: genreAndKeywords.contains('R-15') ? 1 : 0,
    );
  }

  int? _parseNumber(String? value) {
    if (value == null) return null;
    return int.tryParse(value.replaceAll(RegExp(r'[^\d]'), ''));
  }

  int? _metricNumber(String metrics, String label) {
    final value = RegExp('$label：([\\d,]+)').firstMatch(metrics)?.group(1);
    return _parseNumber(value);
  }

  String? _rankingLastUpdated(Element item) {
    final text = item
        .querySelector('.blo_date[title="最終更新日"]')
        ?.text
        .replaceAll(RegExp(r'\s'), '');
    final match = RegExp(
      r'(\d{4})/(\d{2})/(\d{2})(\d{2}):(\d{2})',
    ).firstMatch(text ?? '');
    if (match == null) return null;
    return '${match.group(1)}-${match.group(2)}-${match.group(3)} '
        '${match.group(4)}:${match.group(5)}:00';
  }

  Future<String> _resolveEpisodeUrl(String workId, int index) async {
    final episodes = await fetchToc(workId);
    final episode = episodes.where((item) => item.index == index).firstOrNull;
    if (episode?.url == null) {
      throw StateError('エピソード $index が見つかりません: $workId');
    }
    return episode!.url!;
  }

  String? _shortAuthor(String? headerText) {
    if (headerText == null) return null;
    final match = RegExp(r'作：\s*(.+)$').firstMatch(headerText.trim());
    return match?.group(1)?.trim();
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
      throw HamelnHttpException(response.statusCode ?? -1, url);
    }
    final html = response.data ?? '';
    if (html.contains('投稿者が削除、もしくは間違ったアドレスを指定しています')) {
      throw HamelnWorkNotFoundException(url);
    }
    if (html.contains('R18閲覧確認ページ') &&
        html.contains('あなたは18歳以上ですか？') &&
        html.contains('cookie_set=r18')) {
      throw HamelnAgeConfirmationException(url);
    }
    if (html.contains('<title>Just a moment...</title>') &&
        html.contains('challenge-error-text')) {
      throw HamelnCloudflareChallengeException(url);
    }
    return html;
  }

  void _assertAllowed(Uri uri) {
    if (uri.scheme != 'https' ||
        (uri.host != 'syosetu.org' && uri.host != 'h.syosetu.org')) {
      throw StateError('ハーメルン公式HTTPS URLではありません: $uri');
    }
    final mode = uri.queryParameters['mode'];
    if (uri.path.startsWith('/conv/pdf/') ||
        (mode != null && _isRobotsDisallowedMode(mode))) {
      throw StateError('robots.txtにより取得が禁止されています: $uri');
    }
  }

  bool _isRobotsDisallowedMode(String mode) {
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
}
