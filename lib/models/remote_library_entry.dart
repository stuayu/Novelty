import 'package:novelty/sites/novel_source.dart';

/// 外部サイトのライブラリに登録されている作品を表す最小モデル。
///
/// [title] と [writer] は一覧ページから取得できる場合だけ保持する。
/// 詳細ページの取得を同期の必須条件にしない。
class RemoteLibraryEntry {
  /// コンストラクタ。
  const RemoteLibraryEntry({
    required this.source,
    required this.workId,
    this.title,
    this.writer,
  });

  /// 提供サイト。
  final NovelSource source;

  /// サイト上の作品ID。
  final String workId;

  /// 一覧ページに表示されている作品名。
  final String? title;

  /// 一覧ページに表示されている作者名。
  final String? writer;
}
