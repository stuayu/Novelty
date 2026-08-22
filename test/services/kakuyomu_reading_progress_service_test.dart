import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/repositories/kakuyomu_session_repository.dart';
import 'package:novelty/services/kakuyomu_graphql_service.dart';
import 'package:novelty/services/kakuyomu_reading_progress_service.dart';

class _FakeSessionRepository extends KakuyomuSessionRepository {
  _FakeSessionRepository(this.cookieHeader);

  final String? cookieHeader;

  @override
  Future<String?> buildCookieHeader() async => cookieHeader;
}

void main() {
  const episodeId = '16818023211929635009';
  const position = 'confirmed-position-value';

  group('KakuyomuReadingProgressService', () {
    test('RecordReadingHistoryへepisodeIdとpositionをそのまま送信する', () async {
      KakuyomuGraphqlRequest? captured;
      final graphql = KakuyomuGraphqlService(
        sessionRepository: _FakeSessionRepository('session=test'),
        transport: (request) async {
          captured = request;
          return const KakuyomuGraphqlResponse(
            statusCode: 200,
            body: <String, Object?>{
              'data': <String, Object?>{
                'recordReadingHistory': <String, Object?>{
                  'clientMutationId': null,
                  '__typename': 'RecordReadingHistoryPayload',
                },
              },
            },
          );
        },
      );
      final service = KakuyomuReadingProgressService(graphqlService: graphql);

      expect(
        await service.record(episodeId: episodeId, position: position),
        isTrue,
      );
      expect(captured?.operationName, 'RecordReadingHistory');
      expect(captured?.query, contains('recordReadingHistory(input: \$input)'));
      expect(captured?.variables, const <String, Object?>{
        'input': <String, Object?>{
          'episodeId': episodeId,
          'position': position,
        },
      });
      expect(captured?.cookieHeader, 'session=test');
    });

    test('Cookieが無ければ通信せずfalseを返す', () async {
      var called = false;
      final graphql = KakuyomuGraphqlService(
        sessionRepository: _FakeSessionRepository(null),
        transport: (request) async {
          called = true;
          return const KakuyomuGraphqlResponse(
            statusCode: 200,
            body: <String, Object?>{},
          );
        },
      );
      final service = KakuyomuReadingProgressService(graphqlService: graphql);

      expect(
        await service.record(episodeId: episodeId, position: position),
        isFalse,
      );
      expect(called, isFalse);
    });

    test('HTTP 401と403はfalseを返す', () async {
      for (final statusCode in <int>[401, 403]) {
        final graphql = KakuyomuGraphqlService(
          sessionRepository: _FakeSessionRepository('expired=session'),
          transport: (request) async => KakuyomuGraphqlResponse(
            statusCode: statusCode,
            body: const <String, Object?>{},
          ),
        );
        final service = KakuyomuReadingProgressService(graphqlService: graphql);

        expect(
          await service.record(episodeId: episodeId, position: position),
          isFalse,
        );
      }
    });

    test('GraphQL errorはfalseを返す', () async {
      final graphql = KakuyomuGraphqlService(
        sessionRepository: _FakeSessionRepository('session=test'),
        transport: (request) async {
          return const KakuyomuGraphqlResponse(
            statusCode: 200,
            body: <String, Object?>{
              'errors': <Object?>[
                <String, Object?>{'message': 'mutation failed'},
              ],
            },
          );
        },
      );
      final service = KakuyomuReadingProgressService(graphqlService: graphql);

      expect(
        await service.record(episodeId: episodeId, position: position),
        isFalse,
      );
    });

    test('不正episodeIdと空positionは通信しない', () async {
      var called = false;
      final graphql = KakuyomuGraphqlService(
        sessionRepository: _FakeSessionRepository('session=test'),
        transport: (request) async {
          called = true;
          return const KakuyomuGraphqlResponse(
            statusCode: 200,
            body: <String, Object?>{},
          );
        },
      );
      final service = KakuyomuReadingProgressService(graphqlService: graphql);

      expect(
        await service.record(episodeId: '../auth/login', position: position),
        isFalse,
      );
      expect(
        await service.record(episodeId: episodeId, position: ''),
        isFalse,
      );
      expect(called, isFalse);
    });

    test('通信例外は外へ投げずfalseを返す', () async {
      final graphql = KakuyomuGraphqlService(
        sessionRepository: _FakeSessionRepository('session=test'),
        transport: (request) async => throw Exception('network failed'),
      );
      final service = KakuyomuReadingProgressService(graphqlService: graphql);

      expect(
        await service.record(episodeId: episodeId, position: position),
        isFalse,
      );
    });
  });
}
