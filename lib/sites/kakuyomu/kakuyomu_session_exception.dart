import 'package:novelty/sites/account_sync_adapter.dart';

/// カクヨムの保存済みセッションが失効している場合の例外。
class KakuyomuSessionExpiredException extends AccountSessionExpiredException {
  /// コンストラクタ。
  const KakuyomuSessionExpiredException() : super(clearSessionOnCatch: false);

  @override
  String toString() => 'KakuyomuSessionExpiredException';
}
