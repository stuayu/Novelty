import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/database/database.dart';
import 'package:novelty/repositories/kakuyomu_session_repository.dart';
import 'package:novelty/sites/kakuyomu/kakuyomu_account_sync_adapter.dart';

class _FakeSessionRepository extends KakuyomuSessionRepository {
  @override
  Future<String?> buildCookieHeader() async => 'session=test';
}

void main() {
  group('KakuyomuAccountSyncAdapter reading progress', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.memory();
    });

    tearDown(() async {
      await db.close();
    });

    test('ローカル話数から公式URLを解決しremote episode IDとpositionを送る', () async {
      String? sentWorkId;
      String? sentEpisodeId;
      String? sentPosition;
      final adapter = KakuyomuAccountSyncAdapter(
        sessionRepository: _FakeSessionRepository(),
        db: db,
        episodeUrlResolver: (workId, episode) async {
          expect(workId, '2912051601045930861');
          expect(episode, 3);
          return 'https://kakuyomu.jp/works/2912051601045930861/'
              'episodes/2912051601046590969';
        },
        pushReadingProgress: ({
          required workId,
          required episodeId,
          required position,
        }) async {
          sentWorkId = workId;
          sentEpisodeId = episodeId;
          sentPosition = position;
          return true;
        },
      );

      expect(
        await adapter.pushReadingProgress(
          workId: '2912051601045930861',
          episode: 3,
          position: '#p42',
        ),
        isTrue,
      );
      expect(sentWorkId, '2912051601045930861');
      expect(sentEpisodeId, '2912051601046590969');
      expect(sentPosition, '#p42');
    });

    test('position無しでは既存のカクヨム履歴を上書きしない', () async {
      var resolved = false;
      var pushed = false;
      final adapter = KakuyomuAccountSyncAdapter(
        sessionRepository: _FakeSessionRepository(),
        db: db,
        episodeUrlResolver: (workId, episode) async {
          resolved = true;
          return null;
        },
        pushReadingProgress: ({
          required workId,
          required episodeId,
          required position,
        }) async {
          pushed = true;
          return true;
        },
      );

      expect(
        await adapter.pushReadingProgress(
          workId: '2912051601045930861',
          episode: 3,
        ),
        isFalse,
      );
      expect(resolved, isFalse);
      expect(pushed, isFalse);
    });

    test('別作品URL・別host・不正pathは送信しない', () async {
      for (final url in <String>[
        'https://kakuyomu.jp/works/999/episodes/2912051601046590969',
        'https://example.com/works/2912051601045930861/'
            'episodes/2912051601046590969',
        'https://kakuyomu.jp/auth/login',
      ]) {
        var pushed = false;
        final adapter = KakuyomuAccountSyncAdapter(
          sessionRepository: _FakeSessionRepository(),
          db: db,
          episodeUrlResolver: (workId, episode) async => url,
          pushReadingProgress: ({
            required workId,
            required episodeId,
            required position,
          }) async {
            pushed = true;
            return true;
          },
        );

        expect(
          await adapter.pushReadingProgress(
            workId: '2912051601045930861',
            episode: 3,
            position: '#p2',
          ),
          isFalse,
        );
        expect(pushed, isFalse);
      }
    });

    test('目次URLが無い場合は送信しない', () async {
      var pushed = false;
      final adapter = KakuyomuAccountSyncAdapter(
        sessionRepository: _FakeSessionRepository(),
        db: db,
        episodeUrlResolver: (workId, episode) async => null,
        pushReadingProgress: ({
          required workId,
          required episodeId,
          required position,
        }) async {
          pushed = true;
          return true;
        },
      );

      expect(
        await adapter.pushReadingProgress(
          workId: '2912051601045930861',
          episode: 3,
          position: ':root',
        ),
        isFalse,
      );
      expect(pushed, isFalse);
    });
  });
}
