import 'package:novelty/sites/novel_source.dart';
import 'package:novelty/utils/request_rate_limiter.dart';
import 'package:riverpod/riverpod.dart';

/// サイト単位で共有するリクエスト間隔。
const Map<NovelSource, Duration> siteRequestIntervals = <NovelSource, Duration>{
  NovelSource.narou: Duration(milliseconds: 250),
  NovelSource.kakuyomu: Duration(seconds: 1),
  NovelSource.alphapolis: Duration(seconds: 1),
  NovelSource.hameln: Duration(seconds: 5),
  NovelSource.estar: Duration(seconds: 1),
  // 規約第13条22号に配慮し、確認時の下限1秒より保守的な間隔にする。
  NovelSource.novelup: Duration(seconds: 2),
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

final _hamelnRateLimiterProvider = Provider<RequestRateLimiter>((ref) {
  return RequestRateLimiter(
    interval: siteRequestIntervals[NovelSource.hameln]!,
  );
});

final _estarRateLimiterProvider = Provider<RequestRateLimiter>((ref) {
  return RequestRateLimiter(interval: siteRequestIntervals[NovelSource.estar]!);
});

final _novelupRateLimiterProvider = Provider<RequestRateLimiter>((ref) {
  return RequestRateLimiter(
    interval: siteRequestIntervals[NovelSource.novelup]!,
  );
});

/// アプリ内でサイトごとに単一のレートリミッターを提供する。
Provider<RequestRateLimiter> siteRateLimiterProvider(NovelSource source) {
  return switch (source) {
    NovelSource.narou => _narouRateLimiterProvider,
    NovelSource.kakuyomu => _kakuyomuRateLimiterProvider,
    NovelSource.alphapolis => _alphapolisRateLimiterProvider,
    NovelSource.hameln => _hamelnRateLimiterProvider,
    NovelSource.estar => _estarRateLimiterProvider,
    NovelSource.novelup => _novelupRateLimiterProvider,
  };
}
