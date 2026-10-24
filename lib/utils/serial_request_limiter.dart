/// 同じ接続先への通信を直列化し、開始間隔を制限する。
class SerialRequestLimiter {
  /// リクエスト開始間隔を指定して作成する。
  SerialRequestLimiter({required this.interval});

  /// リクエスト開始間の最小時間。
  final Duration interval;

  final Stopwatch _stopwatch = Stopwatch();
  Future<void> _queue = Future<void>.value();

  /// 前の処理完了後、必要な間隔を空けて [request] を実行する。
  Future<T> run<T>(Future<T> Function() request) {
    final queuedRequest = _queue.then((_) async {
      if (_stopwatch.isRunning) {
        final elapsed = _stopwatch.elapsed;
        if (elapsed < interval) {
          await Future<void>.delayed(interval - elapsed);
        }
        _stopwatch
          ..reset()
          ..start();
      } else {
        _stopwatch.start();
      }
      return request();
    });
    _queue = queuedRequest.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return queuedRequest;
  }
}
