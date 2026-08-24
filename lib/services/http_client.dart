import 'package:dio/dio.dart';
import 'package:novelty/utils/request_rate_limiter.dart';
import 'package:novelty/utils/user_agents.dart';

/// 通信開始までの待機上限。
const noveltyConnectTimeout = Duration(seconds: 15);

/// 通信データの送受信上限。
const noveltyTransferTimeout = Duration(seconds: 30);

/// 429 / 503 再試行の初期待機時間。
const noveltyRetryBaseDelay = Duration(seconds: 1);

/// 429 / 503 の最大再試行回数。
const noveltyMaxRetries = 3;

/// 通信に使う既定の User-Agent。
///
/// 実行中のプラットフォームに対応するプリセットを返す。値を差し替える場合は
/// `lib/utils/user_agents.dart` の [userAgentPresets] を編集する。
/// サイトごとに変えたい場合は [createNoveltyDio] の `userAgent` で上書きする。
String get noveltyUserAgent => defaultUserAgent;

/// 再試行前の待機処理。
typedef RetryDelay = Future<void> Function(Duration duration);

/// 現在時刻を返す処理。
typedef CurrentTime = DateTime Function();

/// Novelty全体で使用するDioを生成する。
Dio createNoveltyDio({
  Duration connectTimeout = noveltyConnectTimeout,
  Duration receiveTimeout = noveltyTransferTimeout,
  Duration sendTimeout = noveltyTransferTimeout,
  int maxRetries = noveltyMaxRetries,
  Duration retryBaseDelay = noveltyRetryBaseDelay,
  RetryDelay? retryDelay,
  CurrentTime? now,
  RequestRateLimiter? rateLimiter,
  String? userAgent,
  UserAgentProfile? userAgentProfile,
}) {
  assert(maxRetries >= 0, 'maxRetriesは0以上である必要があります');
  final dio = Dio(
    BaseOptions(
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
      sendTimeout: sendTimeout,
      headers: <String, Object>{
        'User-Agent':
            userAgent ??
            (userAgentProfile != null
                ? userAgentFor(userAgentProfile)
                : defaultUserAgent),
      },
    ),
  );
  if (rateLimiter != null) {
    attachNoveltyRateLimiter(dio, rateLimiter);
  }
  dio.interceptors.add(
    _RetryBackoffInterceptor(
      dio: dio,
      maxRetries: maxRetries,
      retryBaseDelay: retryBaseDelay,
      delay: retryDelay ?? Future<void>.delayed,
      now: now ?? () => DateTime.now().toUtc(),
    ),
  );
  return dio;
}

/// 既存のDioへサイト共有レートリミッターを追加する。
Dio attachNoveltyRateLimiter(
  Dio dio,
  RequestRateLimiter rateLimiter,
) {
  dio.interceptors.add(_RateLimitInterceptor(rateLimiter));
  return dio;
}

class _RateLimitInterceptor extends Interceptor {
  _RateLimitInterceptor(this._rateLimiter);

  final RequestRateLimiter _rateLimiter;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    await _rateLimiter.wait();
    handler.next(options);
  }
}

class _RetryBackoffInterceptor extends Interceptor {
  _RetryBackoffInterceptor({
    required Dio dio,
    required int maxRetries,
    required Duration retryBaseDelay,
    required RetryDelay delay,
    required CurrentTime now,
  }) : _dio = dio,
       _maxRetries = maxRetries,
       _retryBaseDelay = retryBaseDelay,
       _delay = delay,
       _now = now;

  static const _retryCountKey = 'noveltyRetryCount';

  final Dio _dio;
  final int _maxRetries;
  final Duration _retryBaseDelay;
  final RetryDelay _delay;
  final CurrentTime _now;

  @override
  Future<void> onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) async {
    if (!_shouldRetry(response.statusCode, response.requestOptions)) {
      handler.next(response);
      return;
    }

    try {
      handler.resolve(
        await _retry(response.requestOptions, response.headers),
      );
    } on DioException catch (retryError) {
      handler.reject(retryError);
    }
  }

  @override
  Future<void> onError(
    DioException error,
    ErrorInterceptorHandler handler,
  ) async {
    if (!_shouldRetry(error.response?.statusCode, error.requestOptions)) {
      handler.next(error);
      return;
    }

    try {
      handler.resolve(
        await _retry(error.requestOptions, error.response?.headers),
      );
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }

  bool _shouldRetry(int? statusCode, RequestOptions options) {
    final retryCount = options.extra[_retryCountKey] as int? ?? 0;
    return (statusCode == 429 || statusCode == 503) && retryCount < _maxRetries;
  }

  Future<Response<dynamic>> _retry(
    RequestOptions options,
    Headers? headers,
  ) async {
    final retryCount = options.extra[_retryCountKey] as int? ?? 0;
    final retryAfter = _retryAfter(headers);
    await _delay(retryAfter ?? _retryBaseDelay * (1 << retryCount));
    options.extra[_retryCountKey] = retryCount + 1;
    return _dio.fetch<dynamic>(options);
  }

  Duration? _retryAfter(Headers? headers) {
    final value = headers?.value('retry-after');
    if (value == null) return null;

    final seconds = int.tryParse(value.trim());
    if (seconds != null) {
      return seconds < 0 ? null : Duration(seconds: seconds);
    }

    final retryAt = _parseHttpDate(value.trim());
    if (retryAt == null) return null;
    final remaining = retryAt.difference(_now().toUtc());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  DateTime? _parseHttpDate(String value) {
    final match = RegExp(
      r'^[A-Za-z]{3}, (\d{2}) ([A-Za-z]{3}) (\d{4}) '
      r'(\d{2}):(\d{2}):(\d{2}) GMT$',
    ).firstMatch(value);
    if (match == null) return null;

    const months = <String, int>{
      'Jan': 1,
      'Feb': 2,
      'Mar': 3,
      'Apr': 4,
      'May': 5,
      'Jun': 6,
      'Jul': 7,
      'Aug': 8,
      'Sep': 9,
      'Oct': 10,
      'Nov': 11,
      'Dec': 12,
    };
    final month = months[match.group(2)];
    if (month == null) return null;

    return DateTime.utc(
      int.parse(match.group(3)!),
      month,
      int.parse(match.group(1)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
      int.parse(match.group(6)!),
    );
  }
}
