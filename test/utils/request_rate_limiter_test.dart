import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/providers/site_rate_limiter_provider.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:novelty/utils/request_rate_limiter.dart';
import 'package:riverpod/riverpod.dart';

void main() {
  test('並行呼び出しでも許可時刻をリクエスト間隔ずつ空ける', () {
    fakeAsync((async) {
      final permittedAt = <Duration>[];
      final limiter = RequestRateLimiter(
        interval: const Duration(milliseconds: 100),
        now: () => async.elapsed,
      );

      unawaited(limiter.wait().then((_) => permittedAt.add(async.elapsed)));
      unawaited(limiter.wait().then((_) => permittedAt.add(async.elapsed)));
      unawaited(limiter.wait().then((_) => permittedAt.add(async.elapsed)));

      async.flushMicrotasks();
      expect(permittedAt, <Duration>[Duration.zero]);

      async.elapse(const Duration(milliseconds: 99));
      expect(permittedAt, <Duration>[Duration.zero]);

      async.elapse(const Duration(milliseconds: 1));
      expect(
        permittedAt,
        <Duration>[Duration.zero, const Duration(milliseconds: 100)],
      );

      async.elapse(const Duration(milliseconds: 100));
      expect(
        permittedAt,
        <Duration>[
          Duration.zero,
          const Duration(milliseconds: 100),
          const Duration(milliseconds: 200),
        ],
      );
    });
  });

  test('サイト別インスタンスは互いの待機時間に影響しない', () {
    fakeAsync((async) {
      final kakuyomuPermittedAt = <Duration>[];
      final narouPermittedAt = <Duration>[];
      final kakuyomu = RequestRateLimiter(
        interval: const Duration(seconds: 1),
        now: () => async.elapsed,
      );
      final narou = RequestRateLimiter(
        interval: const Duration(milliseconds: 250),
        now: () => async.elapsed,
      );

      unawaited(
        kakuyomu.wait().then((_) => kakuyomuPermittedAt.add(async.elapsed)),
      );
      unawaited(
        kakuyomu.wait().then((_) => kakuyomuPermittedAt.add(async.elapsed)),
      );
      unawaited(narou.wait().then((_) => narouPermittedAt.add(async.elapsed)));
      unawaited(narou.wait().then((_) => narouPermittedAt.add(async.elapsed)));

      async.flushMicrotasks();
      expect(kakuyomuPermittedAt, <Duration>[Duration.zero]);
      expect(narouPermittedAt, <Duration>[Duration.zero]);

      async.elapse(const Duration(milliseconds: 250));
      expect(
        narouPermittedAt,
        <Duration>[Duration.zero, const Duration(milliseconds: 250)],
      );
      expect(kakuyomuPermittedAt, <Duration>[Duration.zero]);

      async.elapse(const Duration(milliseconds: 750));
      expect(
        kakuyomuPermittedAt,
        <Duration>[Duration.zero, const Duration(seconds: 1)],
      );
    });
  });

  test('同じProviderContainerではサイトごとに単一インスタンスを共有する', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final kakuyomu1 = container.read(
      siteRateLimiterProvider(NovelSource.kakuyomu),
    );
    final kakuyomu2 = container.read(
      siteRateLimiterProvider(NovelSource.kakuyomu),
    );
    final narou = container.read(siteRateLimiterProvider(NovelSource.narou));
    final alphapolis1 = container.read(
      siteRateLimiterProvider(NovelSource.alphapolis),
    );
    final alphapolis2 = container.read(
      siteRateLimiterProvider(NovelSource.alphapolis),
    );
    final hameln1 = container.read(
      siteRateLimiterProvider(NovelSource.hameln),
    );
    final hameln2 = container.read(
      siteRateLimiterProvider(NovelSource.hameln),
    );

    expect(kakuyomu2, same(kakuyomu1));
    expect(alphapolis2, same(alphapolis1));
    expect(hameln2, same(hameln1));
    expect(narou, isNot(same(kakuyomu1)));
    expect(alphapolis1, isNot(same(kakuyomu1)));
    expect(hameln1, isNot(same(kakuyomu1)));
    expect(kakuyomu1.interval, const Duration(seconds: 1));
    expect(alphapolis1.interval, const Duration(seconds: 1));
    expect(hameln1.interval, const Duration(seconds: 3));
    expect(narou.interval, const Duration(milliseconds: 250));
  });
}
