import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/services/kakuyomu_login_check_queue.dart';

void main() {
  test('確認中に届いた画面遷移通知をCookie再確認へ回す', () async {
    final queue = KakuyomuLoginCheckQueue();
    final firstCheckStarted = Completer<void>();
    final finishFirstCheck = Completer<void>();
    var checkCount = 0;

    Future<bool> checkLogin() async {
      checkCount++;
      if (checkCount == 1) {
        firstCheckStarted.complete();
        await finishFirstCheck.future;
        return false;
      }
      return true;
    }

    final firstRequest = queue.request(checkLogin);
    await firstCheckStarted.future;
    final navigationRequest = queue.request(checkLogin);

    expect(checkCount, 1);

    finishFirstCheck.complete();
    await firstRequest;
    await navigationRequest;

    expect(checkCount, 2);
    expect(queue.isCompleted, isTrue);
  });

  test('ログイン確認後の通知は再実行しない', () async {
    final queue = KakuyomuLoginCheckQueue();
    var checkCount = 0;

    await queue.request(() async {
      checkCount++;
      return true;
    });
    await queue.request(() async {
      checkCount++;
      return false;
    });

    expect(checkCount, 1);
    expect(queue.isCompleted, isTrue);
  });
}
