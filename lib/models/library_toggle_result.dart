import 'package:freezed_annotation/freezed_annotation.dart';

part 'library_toggle_result.freezed.dart';

/// ライブラリ登録状態の切り替え操作の結果を表すモデル。
@freezed
class LibraryToggleResult with _$LibraryToggleResult {
  /// ライブラリに追加された結果を作成する。
  const factory LibraryToggleResult.added({
    /// なろう本家へのブックマーク同期に失敗したかどうか（ログイン中のみ意味を持つ）。
    @Default(false) bool narouSyncFailed,
  }) = _Added;

  /// ライブラリから削除された結果を作成する。
  const factory LibraryToggleResult.removed({
    /// なろう本家のブックマーク解除に失敗したかどうか（ログイン中のみ意味を持つ）。
    @Default(false) bool narouSyncFailed,
  }) = _Removed;

  /// ローカルDB操作でエラーが発生した結果を作成する。
  const factory LibraryToggleResult.error() = _Error;
}
