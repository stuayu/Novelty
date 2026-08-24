/// カクヨムの保存済みセッションが失効している場合の例外。
class KakuyomuSessionExpiredException implements Exception {
  /// コンストラクタ。
  const KakuyomuSessionExpiredException();

  @override
  String toString() => 'KakuyomuSessionExpiredException';
}
