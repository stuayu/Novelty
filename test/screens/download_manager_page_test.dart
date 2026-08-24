import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narou_parser/narou_parser.dart';
import 'package:novelty/database/database.dart';
import 'package:novelty/screens/download_manager_page.dart';
import 'package:novelty/sites/novel_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('完了タブに3サイトの作品をsourceとworkIdで表示する', (tester) async {
    final database = AppDatabase.memory();
    addTearDown(database.close);

    const works = <(NovelSource, String, String)>[
      (NovelSource.narou, 'n1234ab', 'なろう作品'),
      (NovelSource.kakuyomu, '16818023211929539879', 'カクヨム作品'),
      (NovelSource.alphapolis, '123456789', 'アルファポリス作品'),
    ];
    for (final (source, workId, title) in works) {
      await database
          .into(database.novels)
          .insert(
            NovelsCompanion(
              source: Value(source),
              workId: Value(workId),
              title: Value(title),
              generalAllNo: const Value(1),
            ),
          );
      await database
          .into(database.episodeContents)
          .insert(
            EpisodeContentsCompanion(
              source: Value(source),
              workId: Value(workId),
              episodeId: const Value(1),
              content: Value([NovelContentElement.plainText(title)]),
            ),
          );
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: const MaterialApp(home: DownloadManagerPage()),
      ),
    );
    await tester.tap(find.text('完了'));
    await tester.pumpAndSettle();

    expect(find.text('なろう作品'), findsOneWidget);
    expect(find.text('カクヨム作品'), findsOneWidget);
    expect(find.text('アルファポリス作品'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
