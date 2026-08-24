/// HTTPリクエストの開始間隔を直列化するレートリミッター。
class RequestRateLimiter {
  /// コンストラクタ。
  RequestRateLimiter({
    required this.interval,
    Duration Function()? now,
  }) : _now = now ?? _createMonotonicClock();

  /// リクエスト間隔。
  final Duration interval;

  final Duration Function() _now;
  Future<void> _tail = Future<void>.value();
  Duration? _lastPermitAt;

  /// 直前の許可から [interval] 以上経過した時点で呼び出しを許可する。
  Future<void> wait() {
    final permit = _tail.then((_) async {
      final lastPermitAt = _lastPermitAt;
      if (lastPermitAt != null) {
        final remaining = interval - (_now() - lastPermitAt);
        if (remaining > Duration.zero) {
          await Future<void>.delayed(remaining);
        }
      }
      _lastPermitAt = _now();
    });
    _tail = permit;
    return permit;
  }

  static Duration Function() _createMonotonicClock() {
    final stopwatch = Stopwatch()..start();
    return () => stopwatch.elapsed;
  }
}
