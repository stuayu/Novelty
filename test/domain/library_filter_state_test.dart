import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/domain/library_filter_state.dart';
import 'package:novelty/utils/value_wrapper.dart';

void main() {
  group('LibraryFilterState', () {
    test('デフォルト値が正しく設定される', () {
      const state = LibraryFilterState();

      expect(state.serialStatus, equals(LibrarySerialStatus.all));
      expect(state.selectedGenre, isNull);
      expect(state.sortOrder, equals(LibrarySortOrder.addedAtDesc));
      expect(state.searchQuery, equals(''));
    });

    test('コンストラクタでフィールドを設定できる', () {
      const state = LibraryFilterState(
        serialStatus: LibrarySerialStatus.ongoing,
        selectedGenre: 1,
        sortOrder: LibrarySortOrder.titleAsc,
        searchQuery: 'テスト',
      );

      expect(state.serialStatus, equals(LibrarySerialStatus.ongoing));
      expect(state.selectedGenre, equals(1));
      expect(state.sortOrder, equals(LibrarySortOrder.titleAsc));
      expect(state.searchQuery, equals('テスト'));
    });

    test('copyWithでフィールドを変更できる', () {
      const state = LibraryFilterState();

      final updated1 = state.copyWith(
        serialStatus: LibrarySerialStatus.completed,
      );
      expect(updated1.serialStatus, equals(LibrarySerialStatus.completed));
      expect(updated1.selectedGenre, isNull);

      final updated2 = updated1.copyWith(selectedGenre: const Value(2));
      expect(updated2.serialStatus, equals(LibrarySerialStatus.completed));
      expect(updated2.selectedGenre, equals(2));

      final updated3 = updated2.copyWith(sortOrder: LibrarySortOrder.titleDesc);
      expect(updated3.sortOrder, equals(LibrarySortOrder.titleDesc));

      final updated4 = updated3.copyWith(searchQuery: 'キーワード');
      expect(updated4.searchQuery, equals('キーワード'));
    });

    test('copyWithでジャンルにnullを明示的に設定できる', () {
      const state = LibraryFilterState(selectedGenre: 1);

      final updated = state.copyWith(selectedGenre: const Value<int?>(null));

      expect(updated.selectedGenre, isNull);
      expect(updated.serialStatus, equals(state.serialStatus));
    });

    test('copyWithでパラメータを省略すると元の値が保持される', () {
      const state = LibraryFilterState(
        selectedGenre: 1,
        sortOrder: LibrarySortOrder.updatedAtDesc,
        searchQuery: '既存の検索語',
      );

      final updated = state.copyWith(
        serialStatus: LibrarySerialStatus.ongoing,
      );

      expect(updated.serialStatus, equals(LibrarySerialStatus.ongoing));
      expect(updated.selectedGenre, equals(1)); // 変更されていない
      expect(updated.sortOrder, equals(LibrarySortOrder.updatedAtDesc));
      expect(updated.searchQuery, equals('既存の検索語'));
    });

    test('同じ値を持つインスタンスは等価', () {
      const state1 = LibraryFilterState(
        serialStatus: LibrarySerialStatus.ongoing,
        selectedGenre: 1,
        sortOrder: LibrarySortOrder.titleAsc,
        searchQuery: 'abc',
      );
      const state2 = LibraryFilterState(
        serialStatus: LibrarySerialStatus.ongoing,
        selectedGenre: 1,
        sortOrder: LibrarySortOrder.titleAsc,
        searchQuery: 'abc',
      );

      expect(state1, equals(state2));
      expect(state1.hashCode, equals(state2.hashCode));
    });

    test('異なる値を持つインスタンスは非等価', () {
      const state1 = LibraryFilterState();
      const state2 = LibraryFilterState(
        serialStatus: LibrarySerialStatus.ongoing,
      );

      expect(state1, isNot(equals(state2)));
    });

    test('toStringが正しい形式を返す', () {
      const state = LibraryFilterState(
        serialStatus: LibrarySerialStatus.ongoing,
        selectedGenre: 1,
        sortOrder: LibrarySortOrder.titleAsc,
        searchQuery: 'abc',
      );

      expect(
        state.toString(),
        'LibraryFilterState(serialStatus: LibrarySerialStatus.ongoing, '
        'selectedGenre: 1, sortOrder: LibrarySortOrder.titleAsc, '
        'searchQuery: abc)',
      );
    });
  });
}
