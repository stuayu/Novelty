import 'package:flutter/foundation.dart';
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

  /// 更新日時が新しい順。
  updatedAtDesc,

  /// 更新日時が古い順。
  updatedAtAsc,

  /// タイトルの昇順（あいうえお順）。
  titleAsc,

  /// タイトルの降順。
  titleDesc,
}

/// ライブラリのフィルタ状態を表すモデル。
@immutable
class LibraryFilterState {
  /// コンストラクタ。
  const LibraryFilterState({
    this.serialStatus = LibrarySerialStatus.all,
    this.selectedGenre,
    this.sortOrder = LibrarySortOrder.addedAtDesc,
    this.searchQuery = '',
  });

  /// 連載状況フィルタ。
  final LibrarySerialStatus serialStatus;

  /// 選択されたジャンル。
  final int? selectedGenre;

  /// ソート順。
  final LibrarySortOrder sortOrder;

  /// タイトル・作者名の検索キーワード。
  final String searchQuery;

  /// フィールドを変更した新しいインスタンスを作成する
  LibraryFilterState copyWith({
    LibrarySerialStatus? serialStatus,
    Value<int?>? selectedGenre,
    LibrarySortOrder? sortOrder,
    String? searchQuery,
  }) {
    return LibraryFilterState(
      serialStatus: serialStatus ?? this.serialStatus,
      selectedGenre: selectedGenre != null
          ? selectedGenre.value
          : this.selectedGenre,
      sortOrder: sortOrder ?? this.sortOrder,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LibraryFilterState &&
          runtimeType == other.runtimeType &&
          serialStatus == other.serialStatus &&
          selectedGenre == other.selectedGenre &&
          sortOrder == other.sortOrder &&
          searchQuery == other.searchQuery;

  @override
  int get hashCode =>
      Object.hash(serialStatus, selectedGenre, sortOrder, searchQuery);

  @override
  String toString() =>
      'LibraryFilterState(serialStatus: $serialStatus, '
      'selectedGenre: $selectedGenre, sortOrder: $sortOrder, '
      'searchQuery: $searchQuery)';
}

/// ライブラリのフィルタ状態を管理するNotifier。
@riverpod
class LibraryFilterStateNotifier extends _$LibraryFilterStateNotifier {
  @override
  LibraryFilterState build() {
    return const LibraryFilterState();
  }

  /// 連載状況フィルタを設定する。
  void setSerialStatus(LibrarySerialStatus value) {
    state = state.copyWith(serialStatus: value);
  }

  /// ジャンルフィルタを設定する。
  void setSelectedGenre(int? genre) {
    state = state.copyWith(
      selectedGenre: genre != null ? Value(genre) : const Value(null),
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
      selectedGenre: const Value(null),
      sortOrder: LibrarySortOrder.addedAtDesc,
    );
  }
}
