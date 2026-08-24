import 'package:novelty/sites/novel_source.dart';
import 'package:novelty/utils/request_rate_limiter.dart';
import 'package:riverpod/riverpod.dart';

/// サイト単位で共有するリクエスト間隔。
const Map<NovelSource, Duration> siteRequestIntervals = <NovelSource, Duration>{
  NovelSource.narou: Duration(milliseconds: 250),
  NovelSource.kakuyomu: Duration(seconds: 1),
  NovelSource.alphapolis: Duration(seconds: 1),
};

final _narouRateLimiterProvider = Provider<RequestRateLimiter>((ref) {
  return RequestRateLimiter(interval: siteRequestIntervals[NovelSource.narou]!);
});

final _kakuyomuRateLimiterProvider = Provider<RequestRateLimiter>((ref) {
  return RequestRateLimiter(
    interval: siteRequestIntervals[NovelSource.kakuyomu]!,
  );
});

final _alphapolisRateLimiterProvider = Provider<RequestRateLimiter>((ref) {
  return RequestRateLimiter(
    interval: siteRequestIntervals[NovelSource.alphapolis]!,
  );
});

/// アプリ内でサイトごとに単一のレートリミッターを提供する。
Provider<RequestRateLimiter> siteRateLimiterProvider(NovelSource source) {
  return switch (source) {
    NovelSource.narou => _narouRateLimiterProvider,
    NovelSource.kakuyomu => _kakuyomuRateLimiterProvider,
    NovelSource.alphapolis => _alphapolisRateLimiterProvider,
  };
}
