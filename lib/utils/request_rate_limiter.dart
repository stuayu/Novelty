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
  Duration? _blockedUntil;

  /// 直前の許可から [interval] 以上経過した時点で呼び出しを許可する。
  Future<void> wait() {
    final permit = _tail.then((_) async {
      final lastPermitAt = _lastPermitAt;
      final now = _now();
      final intervalRemaining = lastPermitAt == null
          ? Duration.zero
          : interval - (now - lastPermitAt);
      final blockedRemaining = _blockedUntil == null
          ? Duration.zero
          : _blockedUntil! - now;
      final remaining = intervalRemaining > blockedRemaining
          ? intervalRemaining
          : blockedRemaining;
      if (remaining > Duration.zero) {
        await Future<void>.delayed(remaining);
      }
      _lastPermitAt = _now();
    });
    _tail = permit;
    return permit;
  }

  /// サーバーの応答に従い、指定時間だけ後続リクエストを止める。
  void pauseFor(Duration duration) {
    if (duration <= Duration.zero) return;
    final blockedUntil = _now() + duration;
    if (_blockedUntil == null || blockedUntil > _blockedUntil!) {
      _blockedUntil = blockedUntil;
    }
  }

  static Duration Function() _createMonotonicClock() {
    final stopwatch = Stopwatch()..start();
    return () => stopwatch.elapsed;
  }
}
