import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/domain/library_filter_state.dart';
import 'package:novelty/sites/novel_site.dart';
import 'package:novelty/widgets/library_filter_sheet.dart';

void main() {
  const testGenres = [
    GenreMaster(id: '101', name: '異世界〔恋愛〕'),
    GenreMaster(id: '201', name: '現実世界〔恋愛〕'),
  ];

  Future<void> pumpSheet(
    WidgetTester tester, {
    required void Function({
      required LibrarySerialStatus serialStatus,
      required String? selectedGenreId,
    })
    onApply,
    LibrarySerialStatus initialSerialStatus = LibrarySerialStatus.all,
    String? initialSelectedGenreId,
    List<GenreMaster> genres = testGenres,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LibraryFilterSheet(
            genres: genres,
            initialSerialStatus: initialSerialStatus,
            initialSelectedGenreId: initialSelectedGenreId,
            onApply: onApply,
          ),
        ),
      ),
    );
  }

  testWidgets('連載状況の3択がすべて表示される', (tester) async {
    await pumpSheet(
      tester,
      onApply: ({required serialStatus, required selectedGenreId}) {},
    );

    expect(find.text('すべて'), findsOneWidget);
    expect(find.text('連載中のみ'), findsOneWidget);
    expect(find.text('完結済みのみ'), findsOneWidget);
  });

  testWidgets('連載状況を選択して適用するとonApplyに反映される', (tester) async {
    LibrarySerialStatus? appliedStatus;
    String? appliedGenreId;

    await pumpSheet(
      tester,
      onApply: ({required serialStatus, required selectedGenreId}) {
        appliedStatus = serialStatus;
        appliedGenreId = selectedGenreId;
      },
    );

    await tester.tap(find.text('完結済みのみ'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('適用'));
    await tester.pumpAndSettle();

    expect(appliedStatus, equals(LibrarySerialStatus.completed));
    expect(appliedGenreId, isNull);
  });

  testWidgets('リセットボタンで初期状態に戻る', (tester) async {
    LibrarySerialStatus? appliedStatus;

    await pumpSheet(
      tester,
      initialSerialStatus: LibrarySerialStatus.ongoing,
      onApply: ({required serialStatus, required selectedGenreId}) {
        appliedStatus = serialStatus;
      },
    );

    await tester.tap(find.text('リセット'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('適用'));
    await tester.pumpAndSettle();

    expect(appliedStatus, equals(LibrarySerialStatus.all));
  });
}
