import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/database/database.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late File dbFile;

  setUp(() {
    dbFile = File(
      '${Directory.systemTemp.path}/novelty_migration_v23_test_'
      '${DateTime.now().microsecondsSinceEpoch}.db',
    );
  });

  tearDown(() {
    if (dbFile.existsSync()) {
      dbFile.deleteSync();
    }
  });

  Future<void> createV22Database(File file) async {
    sqlite3.open(file.path)
      ..execute('''
        CREATE TABLE episode_list_entries (
          source TEXT NOT NULL,
          work_id TEXT NOT NULL,
          episode_id INTEGER NOT NULL,
          subtitle TEXT,
          url TEXT,
          published_at TEXT,
          revised_at TEXT,
          fetched_at INTEGER,
          PRIMARY KEY (source, work_id, episode_id)
        )
      ''')
      ..execute('''
        INSERT INTO episode_list_entries
          (source, work_id, episode_id, subtitle, url, published_at, revised_at)
        VALUES ('kakuyomu', 'work-id', 1, '', '', '', '')
      ''')
      ..execute('''
        INSERT INTO episode_list_entries
          (source, work_id, episode_id, subtitle, url, published_at, revised_at)
        VALUES (
          'kakuyomu',
          'work-id',
          2,
          '第2話',
          'https://example.com/2',
          '2026-01-01',
          '2026-01-02'
        )
      ''')
      ..execute('PRAGMA user_version = 22')
      ..close();
  }

  test('v22からv23で空文字メタデータをNULLへ正規化すること', () async {
    await createV22Database(dbFile);
    final db = AppDatabase.test(NativeDatabase(dbFile));
    addTearDown(db.close);

    final rows = await db
        .customSelect(
          'SELECT subtitle, url, published_at, revised_at '
          'FROM episode_list_entries ORDER BY episode_id',
        )
        .get();

    expect(rows.first.read<String?>('subtitle'), isNull);
    expect(rows.first.read<String?>('url'), isNull);
    expect(rows.first.read<String?>('published_at'), isNull);
    expect(rows.first.read<String?>('revised_at'), isNull);
    expect(rows.last.read<String>('subtitle'), '第2話');
    expect(rows.last.read<String>('url'), 'https://example.com/2');
  });
}
