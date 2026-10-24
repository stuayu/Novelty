import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/utils/serial_request_limiter.dart';

void main() {
  test('前の通信が完了するまで次の通信を開始しない', () async {
    final limiter = SerialRequestLimiter(interval: Duration.zero);
    final firstStarted = Completer<void>();
    final secondStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    var activeRequests = 0;
    var maximumActiveRequests = 0;

    final firstRequest = limiter.run(() async {
      activeRequests++;
      maximumActiveRequests = activeRequests;
      firstStarted.complete();
      await releaseFirst.future;
      activeRequests--;
      return 'first';
    });
    final secondRequest = limiter.run(() async {
      activeRequests++;
      maximumActiveRequests = activeRequests;
      secondStarted.complete();
      activeRequests--;
      return 'second';
    });

    await firstStarted.future;
    await Future<void>.delayed(Duration.zero);
    expect(secondStarted.isCompleted, isFalse);
    expect(maximumActiveRequests, 1);

    releaseFirst.complete();
    expect(await firstRequest, 'first');
    expect(await secondRequest, 'second');
    expect(maximumActiveRequests, 1);
  });
}
