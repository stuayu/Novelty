import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:narou_parser/narou_parser.dart';
import 'package:novelty/database/database.dart';
import 'package:novelty/models/episode.dart';
import 'package:novelty/sites/novel_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EpisodeListEntries / EpisodeContents テーブル', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.memory();
    });

    tearDown(() async {
      await db.close();
    });

    Future<void> insertDummyNovel(String ncode) async {
      await db
          .into(db.novels)
          .insert(
            NovelsCompanion(
              source: const Value(NovelSource.narou),
              workId: Value(ncode),
              title: const Value('dummy title'),
              writer: const Value('dummy writer'),
            ),
          );
    }

    test('目次のupsertと取得ができること', () async {
      const ncode = 'n1234ab';
      await insertDummyNovel(ncode);

      await db.upsertEpisodes([
        const EpisodeListEntriesCompanion(
          source: Value(NovelSource.narou),
          workId: Value(ncode),
          episodeId: Value(1),
          subtitle: Value('第1話'),
          url: Value('https://example.com/1'),
          publishedAt: Value('2024-01-01 00:00:00'),
          revisedAt: Value('2024-01-02 00:00:00'),
        ),
      ]);

      // 目次の取得日時が記録されていること
      final rows = await db.select(db.episodeListEntries).get();
      expect(rows.length, 1);
      expect(rows.single.subtitle, '第1話');
      expect(rows.single.fetchedAt, isNotNull);

      final episodes = await db.getEpisodesRange(
        NovelSource.narou,
        ncode,
        1,
        100,
      );
      expect(episodes.length, 1);
      expect(episodes.single.subtitle, '第1話');
      expect(episodes.single.revised, '2024-01-02 00:00:00');
      expect(episodes.single.isDownloaded, isFalse);
    });

    test('目次の再upsertでメタデータが上書きされること', () async {
      const ncode = 'n1234ab';
      await insertDummyNovel(ncode);

      await db.upsertEpisodes([
        const EpisodeListEntriesCompanion(
          source: Value(NovelSource.narou),
          workId: Value(ncode),
          episodeId: Value(1),
          subtitle: Value('第1話'),
          url: Value('https://example.com/1'),
        ),
      ]);
      await db.upsertEpisodes([
        const EpisodeListEntriesCompanion(
          source: Value(NovelSource.narou),
          workId: Value(ncode),
          episodeId: Value(1),
          subtitle: Value('第1話(改稿)'),
          url: Value('https://example.com/1'),
        ),
      ]);

      final episodes = await db.getEpisodesRange(
        NovelSource.narou,
        ncode,
        1,
        100,
      );
      expect(episodes.single.subtitle, '第1話(改稿)');
    });

    test('カクヨムの有効URLが変わったら対応する本文キャッシュを無効化する', () async {
      const workId = 'work';
      await db.upsertEpisodes([
        const EpisodeListEntriesCompanion(
          source: Value(NovelSource.kakuyomu),
          workId: Value(workId),
          episodeId: Value(1),
          subtitle: Value('旧タイトル'),
          url: Value('https://kakuyomu.jp/works/work/episodes/101'),
        ),
      ]);
      await db.updateEpisodeContent(
        source: NovelSource.kakuyomu,
        workId: workId,
        episodeId: 1,
        content: [NovelContentElement.plainText('旧本文')],
        fetchedAt: 123,
      );

      await db.upsertEpisodes([
        const EpisodeListEntriesCompanion(
          source: Value(NovelSource.kakuyomu),
          workId: Value(workId),
          episodeId: Value(1),
          subtitle: Value('新タイトル'),
          url: Value('https://kakuyomu.jp/works/work/episodes/102'),
        ),
      ]);

      final episode = await db.getEpisodeData(NovelSource.kakuyomu, workId, 1);
      expect(episode?.url, 'https://kakuyomu.jp/works/work/episodes/102');
      expect(episode?.content, isNull);
      expect(episode?.subtitle, '新タイトル');
    });

    test('カクヨム目次のURLが無効なときは既存本文とタイトルを保持する', () async {
      const workId = 'work';
      await db.upsertEpisodes([
        const EpisodeListEntriesCompanion(
          source: Value(NovelSource.kakuyomu),
          workId: Value(workId),
          episodeId: Value(1),
          subtitle: Value('旧タイトル'),
          url: Value('https://kakuyomu.jp/works/work/episodes/101'),
        ),
      ]);
      await db.updateEpisodeContent(
        source: NovelSource.kakuyomu,
        workId: workId,
        episodeId: 1,
        content: [NovelContentElement.plainText('旧本文')],
        fetchedAt: 123,
      );

      await db.upsertEpisodes([
        const EpisodeListEntriesCompanion(
          source: Value(NovelSource.kakuyomu),
          workId: Value(workId),
          episodeId: Value(1),
          subtitle: Value('旧タイトル'),
          url: Value(null),
        ),
      ]);

      final episode = await db.getEpisodeData(NovelSource.kakuyomu, workId, 1);
      expect(episode?.url, isNull);
      expect(episode?.subtitle, '旧タイトル');
      expect(episode?.content, isNotEmpty);
    });

    test('カクヨム目次のURLが無効でも話の識別情報が変わったら本文を無効化する', () async {
      const workId = 'work';
      await db.upsertEpisodes([
        const EpisodeListEntriesCompanion(
          source: Value(NovelSource.kakuyomu),
          workId: Value(workId),
          episodeId: Value(1),
          subtitle: Value('旧タイトル'),
          publishedAt: Value('2024-01-01'),
          url: Value('https://kakuyomu.jp/works/work/episodes/101'),
        ),
      ]);
      await db.updateEpisodeContent(
        source: NovelSource.kakuyomu,
        workId: workId,
        episodeId: 1,
        content: [NovelContentElement.plainText('旧本文')],
        fetchedAt: 123,
      );

      await db.upsertEpisodes([
        const EpisodeListEntriesCompanion(
          source: Value(NovelSource.kakuyomu),
          workId: Value(workId),
          episodeId: Value(1),
          subtitle: Value('新タイトル'),
          publishedAt: Value('2024-02-01'),
          url: Value(null),
        ),
      ]);

      final episode = await db.getEpisodeData(NovelSource.kakuyomu, workId, 1);
      expect(episode?.url, isNull);
      expect(episode?.subtitle, '新タイトル');
      expect(episode?.publishedAt, '2024-02-01');
      expect(episode?.content, isNull);
    });

    test('目次URL更新後に古い本文応答が保存されない', () async {
      const workId = 'work';
      const oldUrl = 'https://kakuyomu.jp/works/work/episodes/101';
      const newUrl = 'https://kakuyomu.jp/works/work/episodes/102';
      await db.upsertEpisodes([
        const EpisodeListEntriesCompanion(
          source: Value(NovelSource.kakuyomu),
          workId: Value(workId),
          episodeId: Value(1),
          url: Value(oldUrl),
        ),
      ]);
      final snapshot = await db.getEpisodeListEntrySnapshot(
        NovelSource.kakuyomu,
        workId,
        1,
      );

      await db.upsertEpisodes([
        const EpisodeListEntriesCompanion(
          source: Value(NovelSource.kakuyomu),
          workId: Value(workId),
          episodeId: Value(1),
          url: Value(newUrl),
        ),
      ]);

      await expectLater(
        db.updateEpisodeContent(
          source: NovelSource.kakuyomu,
          workId: workId,
          episodeId: 1,
          content: [NovelContentElement.plainText('古い本文')],
          fetchedAt: 123,
          url: oldUrl,
          expectedSnapshot: snapshot,
        ),
        throwsA(isA<Exception>()),
      );

      final episode = await db.getEpisodeData(NovelSource.kakuyomu, workId, 1);
      expect(episode?.url, newUrl);
      expect(episode?.content, isNull);
    });

    test('目次の改稿日時が変わっても同じURLの本文キャッシュを保持する', () async {
      const workId = 'work';
      const url = 'https://kakuyomu.jp/works/work/episodes/101';
      await db.upsertEpisodes([
        const EpisodeListEntriesCompanion(
          source: Value(NovelSource.kakuyomu),
          workId: Value(workId),
          episodeId: Value(1),
          url: Value(url),
          revisedAt: Value('2024-01-01'),
        ),
      ]);
      await db.updateEpisodeContent(
        source: NovelSource.kakuyomu,
        workId: workId,
        episodeId: 1,
        content: [NovelContentElement.plainText('旧本文')],
        fetchedAt: 123,
        revisedAt: '2024-01-01',
      );

      await db.upsertEpisodes([
        const EpisodeListEntriesCompanion(
          source: Value(NovelSource.kakuyomu),
          workId: Value(workId),
          episodeId: Value(1),
          url: Value(url),
          revisedAt: Value('2024-02-01'),
        ),
      ]);

      final episode = await db.getEpisodeData(NovelSource.kakuyomu, workId, 1);
      expect(episode?.url, url);
      expect(episode?.content, isNotEmpty);
      final listEpisode = await db.getEpisodesRange(
        NovelSource.kakuyomu,
        workId,
        1,
        1,
      );
      expect(listEpisode.single.revised, '2024-02-01');
    });

    test('新しいカクヨム話の挿入時に本文と既読位置を安定URL基準で移動する', () async {
      const workId = 'work';
      const urls = <String>[
        'https://kakuyomu.jp/works/work/episodes/101',
        'https://kakuyomu.jp/works/work/episodes/102',
        'https://kakuyomu.jp/works/work/episodes/103',
      ];
      await db.upsertEpisodes([
        for (var index = 0; index < urls.length; index++)
          EpisodeListEntriesCompanion(
            source: const Value(NovelSource.kakuyomu),
            workId: const Value(workId),
            episodeId: Value(index + 1),
            url: Value(urls[index]),
          ),
      ]);
      for (var index = 0; index < urls.length; index++) {
        await db.updateEpisodeContent(
          source: NovelSource.kakuyomu,
          workId: workId,
          episodeId: index + 1,
          content: [NovelContentElement.plainText('本文${index + 1}')],
          fetchedAt: index + 10,
        );
      }
      await db.addToHistory(
        const ReadingHistoryCompanion(
          source: Value(NovelSource.kakuyomu),
          workId: Value(workId),
          lastEpisodeId: Value(2),
        ),
      );

      await db.upsertEpisodes([
        const EpisodeListEntriesCompanion(
          source: Value(NovelSource.kakuyomu),
          workId: Value(workId),
          episodeId: Value(1),
          url: Value('https://kakuyomu.jp/works/work/episodes/100'),
        ),
        for (var index = 0; index < urls.length; index++)
          EpisodeListEntriesCompanion(
            source: const Value(NovelSource.kakuyomu),
            workId: const Value(workId),
            episodeId: Value(index + 2),
            url: Value(urls[index]),
          ),
      ]);

      final newEpisode = await db.getEpisodeData(
        NovelSource.kakuyomu,
        workId,
        1,
      );
      expect(newEpisode?.content, isNull);
      for (var index = 0; index < urls.length; index++) {
        final episode = await db.getEpisodeData(
          NovelSource.kakuyomu,
          workId,
          index + 2,
        );
        expect(episode?.url, urls[index]);
        expect(
          (episode!.content!.single as PlainText).text,
          '本文${index + 1}',
        );
      }
      final history =
          await (db.select(
                db.readingHistory,
              )..where((row) => row.source.equalsValue(NovelSource.kakuyomu)))
              .getSingle();
      expect(history.lastEpisodeId, 3);
    });

    test('改稿中の古い本文応答は目次スナップショット不一致で拒否する', () async {
      const workId = 'work';
      const url = 'https://kakuyomu.jp/works/work/episodes/101';
      await db.upsertEpisodes([
        const EpisodeListEntriesCompanion(
          source: Value(NovelSource.kakuyomu),
          workId: Value(workId),
          episodeId: Value(1),
          url: Value(url),
          revisedAt: Value('2024-01-01'),
        ),
      ]);
      final snapshot = await db.getEpisodeListEntrySnapshot(
        NovelSource.kakuyomu,
        workId,
        1,
      );
      await db.upsertEpisodes([
        const EpisodeListEntriesCompanion(
          source: Value(NovelSource.kakuyomu),
          workId: Value(workId),
          episodeId: Value(1),
          url: Value(url),
          revisedAt: Value('2024-02-01'),
        ),
      ]);

      await expectLater(
        db.updateEpisodeContent(
          source: NovelSource.kakuyomu,
          workId: workId,
          episodeId: 1,
          content: [NovelContentElement.plainText('旧応答')],
          fetchedAt: 123,
          url: url,
          expectedSnapshot: snapshot,
        ),
        throwsA(isA<Exception>()),
      );

      final episode = await db.getEpisodeData(NovelSource.kakuyomu, workId, 1);
      expect(episode?.revisedAt, '2024-02-01');
      expect(episode?.content, isNull);
    });

    test('本文の保存と取得ができること', () async {
      const ncode = 'n1234ab';
      await insertDummyNovel(ncode);

      await db.upsertEpisodes([
        const EpisodeListEntriesCompanion(
          source: Value(NovelSource.narou),
          workId: Value(ncode),
          episodeId: Value(1),
          subtitle: Value('第1話'),
          url: Value('https://example.com/1'),
        ),
      ]);

      await db.updateEpisodeContent(
        source: NovelSource.narou,
        workId: ncode,
        episodeId: 1,
        content: [NovelContentElement.plainText('本文テキスト')],
        fetchedAt: 1234567890,
        revisedAt: '2024-02-01 00:00:00',
      );

      final data = await db.getEpisodeData(NovelSource.narou, ncode, 1);
      expect(data, isNotNull);
      expect(data!.subtitle, '第1話');
      expect(data.content, isNotNull);
      expect(data.content!.length, 1);
      expect(data.fetchedAt, 1234567890);
      expect(data.revisedAt, '2024-02-01 00:00:00');

      // 本文取得済みはダウンロード済み扱いになること
      final episodes = await db.getEpisodesRange(
        NovelSource.narou,
        ncode,
        1,
        100,
      );
      expect(episodes.single.isDownloaded, isTrue);
    });

    test('本文の取得日時が目次とは独立して記録されること', () async {
      const ncode = 'n1234ab';
      await insertDummyNovel(ncode);

      await db.updateEpisodeContent(
        source: NovelSource.narou,
        workId: ncode,
        episodeId: 1,
        content: [NovelContentElement.plainText('本文テキスト')],
        fetchedAt: 111,
      );

      final contents = await db.select(db.episodeContents).get();
      expect(contents.length, 1);
      expect(contents.single.fetchedAt, 111);

      // 本文のみの場合でも目次行が作られ、目次の取得日時はNULLのままであること
      final listRows = await db.select(db.episodeListEntries).get();
      expect(listRows.length, 1);
      expect(listRows.single.fetchedAt, isNull);
    });

    test('watchEpisodesRangeが本文の保存を検知すること', () async {
      const ncode = 'n1234ab';
      await insertDummyNovel(ncode);

      await db.upsertEpisodes([
        const EpisodeListEntriesCompanion(
          source: Value(NovelSource.narou),
          workId: Value(ncode),
          episodeId: Value(1),
          subtitle: Value('第1話'),
        ),
      ]);

      final stream = db.watchEpisodesRange(NovelSource.narou, ncode, 1, 100);
      final expectation = expectLater(
        stream,
        emitsInOrder([
          predicate<List<Episode>>(
            (list) => !list.single.isDownloaded,
          ),
          predicate<List<Episode>>(
            (list) => list.single.isDownloaded,
          ),
        ]),
      );

      await Future<void>.delayed(Duration.zero);
      await db.updateEpisodeContent(
        source: NovelSource.narou,
        workId: ncode,
        episodeId: 1,
        content: [NovelContentElement.plainText('本文テキスト')],
        fetchedAt: 222,
      );

      await expectation;
    });

    test('取得日時がNULLの行が含まれる場合、最古取得日時はNULLを返すこと', () async {
      const ncode = 'n1234ab';
      await insertDummyNovel(ncode);

      // updateEpisodeContentを直接呼ぶと、目次行は作られるがfetchedAtはNULLのまま
      await db.updateEpisodeContent(
        source: NovelSource.narou,
        workId: ncode,
        episodeId: 1,
        content: [NovelContentElement.plainText('本文テキスト')],
        fetchedAt: 222,
      );

      // episodeId=1の目次行はfetchedAtがNULLのままであること
      final listRows = await db.select(db.episodeListEntries).get();
      expect(listRows.single.fetchedAt, isNull);

      // NULL行が含まれるため、最古取得日時はNULL（TTL切れ）として返されること
      final oldest = await db.getEpisodeListOldestFetchedAt(
        NovelSource.narou,
        ncode,
        1,
        100,
      );
      expect(oldest, isNull);
    });

    test('全行の取得日時が設定されている場合、最古取得日時を返すこと', () async {
      const ncode = 'n1234ab';
      await insertDummyNovel(ncode);

      await db
          .into(db.episodeListEntries)
          .insert(
            const EpisodeListEntriesCompanion(
              source: Value(NovelSource.narou),
              workId: Value(ncode),
              episodeId: Value(1),
              subtitle: Value('第1話'),
              url: Value('https://example.com/1'),
              fetchedAt: Value(1000),
            ),
          );

      final oldest = await db.getEpisodeListOldestFetchedAt(
        NovelSource.narou,
        ncode,
        1,
        100,
      );
      expect(oldest, 1000);
    });
  });
}
