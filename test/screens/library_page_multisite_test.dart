import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/database/database.dart';
import 'package:novelty/repositories/novel_repository.dart';
import 'package:novelty/screens/library_page.dart';

void main() {
  testWidgets('ソースがすべてのときジャンル絞り込みを無効化する', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryNovelsProvider.overrideWith((ref) => Stream.value([])),
          libraryMetadataRefresherProvider.overrideWith((ref) async {}),
        ],
        child: const MaterialApp(home: LibraryPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.filter_list));
    await tester.pumpAndSettle();

    expect(find.text('サイトを選択するとジャンルを指定できます'), findsOneWidget);
    expect(find.text('異世界〔恋愛〕'), findsNothing);
  });
}
