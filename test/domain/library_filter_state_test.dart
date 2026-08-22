import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/domain/library_filter_state.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:novelty/utils/value_wrapper.dart';

void main() {
  group('LibraryFilterState', () {
    test('デフォルト値が正しく設定される', () {
      const state = LibraryFilterState();

      expect(state.source, isNull);
      expect(state.serialStatus, equals(LibrarySerialStatus.all));
      expect(state.selectedGenreId, isNull);
      expect(state.sortOrder, equals(LibrarySortOrder.addedAtDesc));
      expect(state.searchQuery, equals(''));
    });

    test('コンストラクタでフィールドを設定できる', () {
      const state = LibraryFilterState(
        source: NovelSource.kakuyomu,
        serialStatus: LibrarySerialStatus.ongoing,
        selectedGenreId: 'FANTASY',
        sortOrder: LibrarySortOrder.titleAsc,
        searchQuery: 'テスト',
      );

      expect(state.source, NovelSource.kakuyomu);
      expect(state.serialStatus, equals(LibrarySerialStatus.ongoing));
      expect(state.selectedGenreId, equals('FANTASY'));
      expect(state.sortOrder, equals(LibrarySortOrder.titleAsc));
      expect(state.searchQuery, equals('テスト'));
    });

    test('copyWithでフィールドを変更できる', () {
      const state = LibraryFilterState();

      final updated1 = state.copyWith(serialStatus: LibrarySerialStatus.ongoing);
      expect(updated1.serialStatus, equals(LibrarySerialStatus.ongoing));
      expect(updated1.selectedGenreId, isNull);

      final updated2 = updated1.copyWith(
        selectedGenreId: const Value('FANTASY'),
        source: const Value(NovelSource.kakuyomu),
      );
      expect(updated2.serialStatus, equals(LibrarySerialStatus.ongoing));
      expect(updated2.selectedGenreId, equals('FANTASY'));
      expect(updated2.source, NovelSource.kakuyomu);

      final updated3 = updated2.copyWith(sortOrder: LibrarySortOrder.titleDesc);
      expect(updated3.sortOrder, equals(LibrarySortOrder.titleDesc));

      final updated4 = updated3.copyWith(searchQuery: 'キーワード');
      expect(updated4.searchQuery, equals('キーワード'));
    });

    test('copyWithでジャンルにnullを明示的に設定できる', () {
      const state = LibraryFilterState(selectedGenreId: 'FANTASY');

      final updated = state.copyWith(
        selectedGenreId: const Value<String?>(null),
      );

      expect(updated.selectedGenreId, isNull);
      expect(updated.serialStatus, equals(state.serialStatus));
    });

    test('copyWithでパラメータを省略すると元の値が保持される', () {
      const state = LibraryFilterState(
        selectedGenreId: 'FANTASY',
        sortOrder: LibrarySortOrder.updatedAtDesc,
        searchQuery: '既存の検索語',
      );

      final updated = state.copyWith(
        serialStatus: LibrarySerialStatus.ongoing,
      );

      expect(updated.serialStatus, equals(LibrarySerialStatus.ongoing));
      expect(updated.selectedGenreId, equals('FANTASY')); // 変更されていない
      expect(updated.sortOrder, equals(LibrarySortOrder.updatedAtDesc));
      expect(updated.searchQuery, equals('既存の検索語'));
    });

    test('同じ値を持つインスタンスは等価', () {
      const state1 = LibraryFilterState(
        source: NovelSource.kakuyomu,
        serialStatus: LibrarySerialStatus.ongoing,
        selectedGenreId: 'FANTASY',
        sortOrder: LibrarySortOrder.titleAsc,
        searchQuery: 'abc',
      );
      const state2 = LibraryFilterState(
        source: NovelSource.kakuyomu,
        serialStatus: LibrarySerialStatus.ongoing,
        selectedGenreId: 'FANTASY',
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
        source: NovelSource.kakuyomu,
        serialStatus: LibrarySerialStatus.ongoing,
        selectedGenreId: 'FANTASY',
        sortOrder: LibrarySortOrder.titleAsc,
        searchQuery: 'abc',
      );

      expect(
        state.toString(),
        'LibraryFilterState(source: NovelSource.kakuyomu, '
        'serialStatus: LibrarySerialStatus.ongoing, '
        'selectedGenreId: FANTASY, sortOrder: LibrarySortOrder.titleAsc, '
        'searchQuery: abc)',
      );
    });
  });

  group('LibraryFilterStateNotifier', () {
    test('setSourceがジャンルフィルタをリセットして状態を更新する', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container
          .read(libraryFilterStateProvider.notifier)
        ..setSelectedGenreId('FANTASY')
        ..setSerialStatus(LibrarySerialStatus.ongoing)
        ..setSource(NovelSource.kakuyomu);

      final state = container.read(libraryFilterStateProvider);
      expect(state.source, NovelSource.kakuyomu);
      // サイト切替時はジャンルフィルタがリセットされる
      expect(state.selectedGenreId, isNull);
      expect(state.serialStatus, LibrarySerialStatus.ongoing);
    });

    test('setSelectedGenreId / setSerialStatus が状態を更新する', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container
          .read(libraryFilterStateProvider.notifier)
        ..setSource(NovelSource.narou)
        ..setSelectedGenreId('201')
        ..setSerialStatus(LibrarySerialStatus.ongoing);

      final state = container.read(libraryFilterStateProvider);
      expect(state.source, NovelSource.narou);
      expect(state.selectedGenreId, '201');
      expect(state.serialStatus, LibrarySerialStatus.ongoing);
    });

    test('setSortOrder / setSearchQuery が状態を更新する', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container
          .read(libraryFilterStateProvider.notifier)
        ..setSortOrder(LibrarySortOrder.titleAsc)
        ..setSearchQuery('検索語');

      final state = container.read(libraryFilterStateProvider);
      expect(state.sortOrder, LibrarySortOrder.titleAsc);
      expect(state.searchQuery, '検索語');
    });

    test('resetが検索キーワード以外を初期状態に戻す', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container
          .read(libraryFilterStateProvider.notifier)
        ..setSelectedGenreId('FANTASY')
        ..setSerialStatus(LibrarySerialStatus.ongoing)
        ..setSortOrder(LibrarySortOrder.titleAsc)
        ..setSearchQuery('検索語')
        ..reset();

      final state = container.read(libraryFilterStateProvider);
      expect(state.serialStatus, LibrarySerialStatus.all);
      expect(state.selectedGenreId, isNull);
      expect(state.sortOrder, LibrarySortOrder.addedAtDesc);
      // 検索キーワードはresetの対象外
      expect(state.searchQuery, '検索語');
    });
  });
}
