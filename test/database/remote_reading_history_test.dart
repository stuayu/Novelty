import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/database/database.dart';
import 'package:novelty/sites/kakuyomu/kakuyomu_history_parser.dart';
import 'package:novelty/sites/novel_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('カクヨム閲覧履歴を保存し、新しい日付だけローカル履歴へ反映する', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    const workId = '1000000000000000001';
    const remoteEpisodeId = '1000000000000000002';
    await db
        .into(db.novels)
        .insert(
          const NovelsCompanion(
            source: Value(NovelSource.kakuyomu),
            workId: Value(workId),
            title: Value('テスト作品'),
          ),
        );
    await db.upsertEpisodes([
      const EpisodeListEntriesCompanion(
        source: Value(NovelSource.kakuyomu),
        workId: Value(workId),
        episodeId: Value(10),
        url: Value(
          'https://kakuyomu.jp/works/$workId/episodes/$remoteEpisodeId',
        ),
      ),
    ]);

    final first = await db.mergeKakuyomuReadingHistories([
      KakuyomuHistoryEntry(
        source: NovelSource.kakuyomu,
        workId: workId,
        episodeId: remoteEpisodeId,
        lastReadAt: DateTime(2026, 8, 23),
      ),
    ]);
    expect(first.inserted, 1);
    expect((await db.getHistory()).single.lastEpisode, 10);
    expect(
      DateTime.fromMillisecondsSinceEpoch(
        (await db.getHistory()).single.viewedAt,
      ),
      DateTime(2026, 8, 23),
    );

    final older = await db.mergeKakuyomuReadingHistories([
      KakuyomuHistoryEntry(
        source: NovelSource.kakuyomu,
        workId: workId,
        episodeId: remoteEpisodeId,
        lastReadAt: DateTime(2026, 8, 22),
      ),
    ]);
    expect(older.updated, 0);
    expect(
      DateTime.fromMillisecondsSinceEpoch(
        (await db.getHistory()).single.viewedAt,
      ),
      DateTime(2026, 8, 23),
    );
  });

  test('watchHistoryがカクヨム閲覧履歴の同期直後に更新される', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    const workId = '1000000000000000001';
    const remoteEpisodeId = '1000000000000000002';
    await db
        .into(db.novels)
        .insert(
          const NovelsCompanion(
            source: Value(NovelSource.kakuyomu),
            workId: Value(workId),
            title: Value('テスト作品'),
          ),
        );
    await db.upsertEpisodes([
      const EpisodeListEntriesCompanion(
        source: Value(NovelSource.kakuyomu),
        workId: Value(workId),
        episodeId: Value(10),
        url: Value(
          'https://kakuyomu.jp/works/$workId/episodes/$remoteEpisodeId',
        ),
      ),
    ]);

    final expectation = expectLater(
      db.watchHistory(),
      emitsInOrder([
        isEmpty,
        predicate<List<HistoryData>>(
          (histories) =>
              histories.length == 1 && histories.single.lastEpisode == 10,
        ),
      ]),
    );

    await Future<void>.delayed(Duration.zero);
    await db.mergeKakuyomuReadingHistories([
      KakuyomuHistoryEntry(
        source: NovelSource.kakuyomu,
        workId: workId,
        episodeId: remoteEpisodeId,
        lastReadAt: DateTime(2026, 8, 23),
      ),
    ]);

    await expectation;
  });

  test('Novelty未登録作品のremote履歴も履歴画面へ反映する', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    const workId = '1000000000000000003';
    const remoteEpisodeId = '1000000000000000004';

    await db.upsertEpisodes([
      const EpisodeListEntriesCompanion(
        source: Value(NovelSource.kakuyomu),
        workId: Value(workId),
        episodeId: Value(3),
        url: Value(
          'https://kakuyomu.jp/works/$workId/episodes/$remoteEpisodeId',
        ),
      ),
    ]);

    await db.mergeKakuyomuReadingHistories([
      KakuyomuHistoryEntry(
        source: NovelSource.kakuyomu,
        workId: workId,
        title: 'リモート作品',
        episodeTitle: '第三話',
        episodeId: remoteEpisodeId,
        lastReadAt: DateTime(2026, 8, 24),
      ),
    ]);

    final history = await db.getHistory();
    expect(history, hasLength(1));
    expect(history.single.title, 'リモート作品');
    expect(history.single.lastEpisode, 3);
  });
}
