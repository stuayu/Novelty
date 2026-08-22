import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/repositories/kakuyomu_session_repository.dart';
import 'package:novelty/services/kakuyomu_reading_progress_service.dart';

class _FakeSessionRepository extends KakuyomuSessionRepository {
  _FakeSessionRepository(this.cookieHeader);

  final String? cookieHeader;

  @override
  Future<String?> buildCookieHeader() async => cookieHeader;
}

void main() {
  const workId = '2912051601045930861';
  const episodeId = '2912051601046590969';

  group('KakuyomuReadingProgressService', () {
    test('実viewerと同じhistory URLへpositionをPOSTする', () async {
      KakuyomuReadingProgressRequest? captured;
      final service = KakuyomuReadingProgressService(
        sessionRepository: _FakeSessionRepository('session=test'),
        transport: (request) async {
          captured = request;
          return const KakuyomuReadingProgressResponse(statusCode: 204);
        },
      );

      expect(
        await service.record(
          workId: workId,
          episodeId: episodeId,
          position: '#p42',
        ),
        isTrue,
      );
      expect(
        captured?.url.toString(),
        'https://kakuyomu.jp/works/$workId/episodes/$episodeId/history',
      );
      expect(captured?.position, '#p42');
      expect(captured?.cookieHeader, 'session=test');
    });

    test(':rootも実viewerの有効なpositionとして送信できる', () async {
      KakuyomuReadingProgressRequest? captured;
      final service = KakuyomuReadingProgressService(
        sessionRepository: _FakeSessionRepository('session=test'),
        transport: (request) async {
          captured = request;
          return const KakuyomuReadingProgressResponse(statusCode: 200);
        },
      );

      expect(
        await service.record(
          workId: workId,
          episodeId: episodeId,
          position: ':root',
        ),
        isTrue,
      );
      expect(captured?.position, ':root');
    });

    test('Cookieが無ければ通信せずfalseを返す', () async {
      var called = false;
      final service = KakuyomuReadingProgressService(
        sessionRepository: _FakeSessionRepository(null),
        transport: (request) async {
          called = true;
          return const KakuyomuReadingProgressResponse(statusCode: 200);
        },
      );

      expect(
        await service.record(
          workId: workId,
          episodeId: episodeId,
          position: '#p1',
        ),
        isFalse,
      );
      expect(called, isFalse);
    });

    test('リダイレクト・認証エラー・サーバーエラーはfalseを返す', () async {
      for (final statusCode in <int>[302, 401, 403, 500]) {
        final service = KakuyomuReadingProgressService(
          sessionRepository: _FakeSessionRepository('expired=session'),
          transport: (request) async =>
              KakuyomuReadingProgressResponse(statusCode: statusCode),
        );

        expect(
          await service.record(
            workId: workId,
            episodeId: episodeId,
            position: '#p1',
          ),
          isFalse,
        );
      }
    });

    test('不正IDと未確認positionは通信しない', () async {
      var called = false;
      final service = KakuyomuReadingProgressService(
        sessionRepository: _FakeSessionRepository('session=test'),
        transport: (request) async {
          called = true;
          return const KakuyomuReadingProgressResponse(statusCode: 200);
        },
      );

      expect(
        await service.record(
          workId: '../auth/login',
          episodeId: episodeId,
          position: '#p1',
        ),
        isFalse,
      );
      expect(
        await service.record(
          workId: workId,
          episodeId: '../auth/login',
          position: '#p1',
        ),
        isFalse,
      );
      expect(
        await service.record(
          workId: workId,
          episodeId: episodeId,
          position: '42',
        ),
        isFalse,
      );
      expect(
        await service.record(
          workId: workId,
          episodeId: episodeId,
          position: ':end',
        ),
        isFalse,
      );
      expect(called, isFalse);
    });

    test('通信例外は外へ投げずfalseを返す', () async {
      final service = KakuyomuReadingProgressService(
        sessionRepository: _FakeSessionRepository('session=test'),
        transport: (request) async => throw Exception('network failed'),
      );

      expect(
        await service.record(
          workId: workId,
          episodeId: episodeId,
          position: '#p1',
        ),
        isFalse,
      );
    });
  });
}
