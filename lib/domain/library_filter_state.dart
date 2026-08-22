import 'package:flutter/foundation.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:novelty/utils/value_wrapper.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'library_filter_state.g.dart';

/// ライブラリの連載状況フィルタ。
enum LibrarySerialStatus {
  /// すべての作品を表示する。
  all,

  /// 連載中の作品のみ表示する。
  ongoing,

  /// 完結済み・短編の作品のみ表示する。
  completed,
}

/// ライブラリのソート順。
enum LibrarySortOrder {
  /// 追加日時が新しい順（デフォルト）。
  addedAtDesc,

  /// 追加日時が古い順。
  addedAtAsc,

  /// 最新エピソード掲載日（general_lastup）が新しい順。
  updatedAtDesc,

  /// 最新エピソード掲載日（general_lastup）が古い順。
  updatedAtAsc,

  /// タイトルの昇順（あいうえお順）。
  titleAsc,

  /// タイトルの降順。
  titleDesc,

  /// アプリの閲覧履歴で最近読んだ順。
  lastReadDesc,

  /// アプリの閲覧履歴で読んだのが古い順。
  lastReadAsc,
}

/// ライブラリのフィルタ状態を表すモデル。
@immutable
class LibraryFilterState {
  /// コンストラクタ。
  const LibraryFilterState({
    this.source,
    this.serialStatus = LibrarySerialStatus.all,
    this.selectedGenreId,
    this.sortOrder = LibrarySortOrder.addedAtDesc,
    this.searchQuery = '',
  });

  /// 絞り込む提供サイト。null はすべてのサイト。
  final NovelSource? source;

  /// 連載状況フィルタ。
  final LibrarySerialStatus serialStatus;

  /// 選択されたジャンルID（サイト共通の文字列ID）。
  final String? selectedGenreId;

  /// ソート順。
  final LibrarySortOrder sortOrder;

  /// タイトル・作者名の検索キーワード。
  final String searchQuery;

  /// フィールドを変更した新しいインスタンスを作成する
  LibraryFilterState copyWith({
    Value<NovelSource?>? source,
    LibrarySerialStatus? serialStatus,
    Value<String?>? selectedGenreId,
    LibrarySortOrder? sortOrder,
    String? searchQuery,
  }) {
    return LibraryFilterState(
      source: source != null ? source.value : this.source,
      serialStatus: serialStatus ?? this.serialStatus,
      selectedGenreId: selectedGenreId != null
          ? selectedGenreId.value
          : this.selectedGenreId,
      sortOrder: sortOrder ?? this.sortOrder,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LibraryFilterState &&
          runtimeType == other.runtimeType &&
          source == other.source &&
          serialStatus == other.serialStatus &&
          selectedGenreId == other.selectedGenreId &&
          sortOrder == other.sortOrder &&
          searchQuery == other.searchQuery;

  @override
  int get hashCode => Object.hash(
    source,
    serialStatus,
    selectedGenreId,
    sortOrder,
    searchQuery,
  );

  @override
  String toString() =>
      'LibraryFilterState(source: $source, serialStatus: $serialStatus, '
      'selectedGenreId: $selectedGenreId, sortOrder: $sortOrder, '
      'searchQuery: $searchQuery)';
}

/// ライブラリのフィルタ状態を管理するNotifier。
@riverpod
class LibraryFilterStateNotifier extends _$LibraryFilterStateNotifier {
  @override
  LibraryFilterState build() {
    return const LibraryFilterState();
  }

  /// サイト絞り込みフィルタを設定する。
  void setSource(NovelSource? source) {
    // サイトを切り替えたらジャンルフィルタはリセットする
    state = LibraryFilterState(
      source: source,
      serialStatus: state.serialStatus,
      sortOrder: state.sortOrder,
      searchQuery: state.searchQuery,
    );
  }

  /// 連載状況フィルタを設定する。
  void setSerialStatus(LibrarySerialStatus value) {
    state = state.copyWith(serialStatus: value);
  }

  /// ジャンルフィルタを設定する。
  void setSelectedGenreId(String? genreId) {
    state = state.copyWith(
      selectedGenreId: genreId != null ? Value(genreId) : const Value(null),
    );
  }

  /// ソート順を設定する。
  void setSortOrder(LibrarySortOrder value) {
    state = state.copyWith(sortOrder: value);
  }

  /// 検索キーワードを設定する。
  void setSearchQuery(String value) {
    state = state.copyWith(searchQuery: value);
  }

  /// フィルタ状態をリセットする（検索キーワードは対象外）。
  void reset() {
    state = state.copyWith(
      serialStatus: LibrarySerialStatus.all,
      selectedGenreId: const Value(null),
      sortOrder: LibrarySortOrder.addedAtDesc,
    );
  }
}
