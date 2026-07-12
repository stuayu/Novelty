import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/domain/library_filter_state.dart';
import 'package:novelty/widgets/library_sort_sheet.dart';

void main() {
  Future<void> pumpSheet(
    WidgetTester tester, {
    required LibrarySortOrder currentOrder,
    required ValueChanged<LibrarySortOrder> onOrderSelected,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LibrarySortSheet(
            currentOrder: currentOrder,
            onOrderSelected: onOrderSelected,
          ),
        ),
      ),
    );
  }

  testWidgets('8つのソート項目がすべて表示される', (tester) async {
    await pumpSheet(
      tester,
      currentOrder: LibrarySortOrder.addedAtDesc,
      onOrderSelected: (_) {},
    );

    expect(find.text('追加日時が新しい順'), findsOneWidget);
    expect(find.text('追加日時が古い順'), findsOneWidget);
    expect(find.text('最新話の掲載が新しい順'), findsOneWidget);
    expect(find.text('最新話の掲載が古い順'), findsOneWidget);
    expect(find.text('タイトル（あいうえお順）'), findsOneWidget);
    expect(find.text('タイトル（逆順）'), findsOneWidget);

    // 閲覧履歴グループはリスト下部にあるためスクロールしてから確認する
    await tester.scrollUntilVisible(find.text('最近読んだ順'), 200);
    expect(find.text('最近読んだ順'), findsOneWidget);
    expect(find.text('最後に読んだのが古い順'), findsOneWidget);
  });

  testWidgets('項目をタップするとonOrderSelectedが呼ばれる', (tester) async {
    LibrarySortOrder? selected;

    await pumpSheet(
      tester,
      currentOrder: LibrarySortOrder.addedAtDesc,
      onOrderSelected: (value) => selected = value,
    );

    await tester.ensureVisible(find.text('タイトル（あいうえお順）'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('タイトル（あいうえお順）'));
    await tester.pumpAndSettle();

    expect(selected, equals(LibrarySortOrder.titleAsc));
  });

  testWidgets('現在のソート順のRadioListTileが選択状態になる', (tester) async {
    await pumpSheet(
      tester,
      currentOrder: LibrarySortOrder.updatedAtDesc,
      onOrderSelected: (_) {},
    );

    final radioGroup = tester.widget<RadioGroup<LibrarySortOrder>>(
      find.byType(RadioGroup<LibrarySortOrder>),
    );
    expect(radioGroup.groupValue, equals(LibrarySortOrder.updatedAtDesc));
  });
}
