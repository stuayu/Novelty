/// 確認中に届いた画面遷移通知を、次のログイン確認へ回す。
class KakuyomuLoginCheckQueue {
  bool _isRunning = false;
  bool _isCompleted = false;
  Future<bool> Function()? _pendingCheck;

  /// ログイン確認が成功済みかどうか。
  bool get isCompleted => _isCompleted;

  /// 確認中の通知は最後のものを保留し、現在の確認後に再実行する。
  Future<void> request(Future<bool> Function() check) async {
    if (_isCompleted) return;
    if (_isRunning) {
      _pendingCheck = check;
      return;
    }

    _isRunning = true;
    try {
      Future<bool> Function()? nextCheck = check;
      while (nextCheck != null && !_isCompleted) {
        _pendingCheck = null;
        _isCompleted = await nextCheck();
        nextCheck = _isCompleted ? null : _pendingCheck;
      }
    } finally {
      _isRunning = false;
    }
  }
}
