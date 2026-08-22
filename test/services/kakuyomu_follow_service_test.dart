import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/repositories/kakuyomu_session_repository.dart';
import 'package:novelty/services/kakuyomu_follow_service.dart';
import 'package:novelty/services/kakuyomu_graphql_service.dart';
import 'package:novelty/sites/account_sync_adapter.dart';

class _FakeSessionRepository extends KakuyomuSessionRepository {
  _FakeSessionRepository(this.cookieHeader);

  final String? cookieHeader;

  @override
  Future<String?> buildCookieHeader() async => cookieHeader;
}

void main() {
  group('KakuyomuFollowService', () {
    const workId = '16818023211929539879';

    test('FollowWorkへworkIdを送信して成功する', () async {
      KakuyomuGraphqlRequest? captured;
      final graphql = KakuyomuGraphqlService(
        sessionRepository: _FakeSessionRepository('session=test'),
        transport: (request) async {
          captured = request;
          return const KakuyomuGraphqlResponse(
            statusCode: 200,
            body: <String, Object?>{
              'data': <String, Object?>{
                'followWork': <String, Object?>{'__typename': 'FollowWorkPayload'},
              },
            },
          );
        },
      );
      final service = KakuyomuFollowService(
        graphqlService: graphql,
        sessionValidator: () async => true,
      );

      final result = await service.followWork(workId);

      expect(result, AccountSyncOutcome.success);
      expect(captured?.operationName, 'FollowWork');
      expect(captured?.variables, const <String, Object?>{
        'input': <String, Object?>{'workId': workId},
      });
      expect(captured?.query, contains('followWork(input: \$input)'));
      expect(captured?.cookieHeader, 'session=test');
    });

    test('UnfollowWorksへworkIds配列を送信して成功する', () async {
      KakuyomuGraphqlRequest? captured;
      final graphql = KakuyomuGraphqlService(
        sessionRepository: _FakeSessionRepository('session=test'),
        transport: (request) async {
          captured = request;
          return const KakuyomuGraphqlResponse(
            statusCode: 200,
            body: <String, Object?>{
              'data': <String, Object?>{
                'unfollowWorks': <String, Object?>{
                  '__typename': 'UnfollowWorksPayload',
                },
              },
            },
          );
        },
      );
      final service = KakuyomuFollowService(
        graphqlService: graphql,
        sessionValidator: () async => true,
      );

      final result = await service.unfollowWork(workId);

      expect(result, AccountSyncOutcome.success);
      expect(captured?.operationName, 'UnfollowWorks');
      expect(captured?.variables, const <String, Object?>{
        'input': <String, Object?>{
          'workIds': <String>[workId],
        },
      });
      expect(captured?.query, contains('unfollowWorks(input: \$input)'));
    });

    test('セッションが無効ならGraphQLを呼ばず未ログインを返す', () async {
      var called = false;
      final graphql = KakuyomuGraphqlService(
        sessionRepository: _FakeSessionRepository('expired=session'),
        transport: (request) async {
          called = true;
          return const KakuyomuGraphqlResponse(
            statusCode: 200,
            body: <String, Object?>{},
          );
        },
      );
      final service = KakuyomuFollowService(
        graphqlService: graphql,
        sessionValidator: () async => false,
      );

      expect(
        await service.followWork(workId),
        AccountSyncOutcome.notLoggedIn,
      );
      expect(called, isFalse);
    });

    test('GraphQL UNAUTHORIZEDは未ログインを返す', () async {
      final graphql = KakuyomuGraphqlService(
        sessionRepository: _FakeSessionRepository('expired=session'),
        transport: (request) async {
          return const KakuyomuGraphqlResponse(
            statusCode: 200,
            body: <String, Object?>{
              'errors': <Object?>[
                <String, Object?>{
                  'message': 'Authentication required',
                  'extensions': <String, Object?>{'code': 'UNAUTHORIZED'},
                },
              ],
            },
          );
        },
      );
      final service = KakuyomuFollowService(
        graphqlService: graphql,
        sessionValidator: () async => true,
      );

      expect(
        await service.followWork(workId),
        AccountSyncOutcome.notLoggedIn,
      );
    });

    test('その他のGraphQL errorsは失敗を返す', () async {
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
      final service = KakuyomuFollowService(
        graphqlService: graphql,
        sessionValidator: () async => true,
      );

      expect(await service.followWork(workId), AccountSyncOutcome.failed);
    });

    test('数値でないworkIdは通信せず失敗を返す', () async {
      var validated = false;
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
      final service = KakuyomuFollowService(
        graphqlService: graphql,
        sessionValidator: () async {
          validated = true;
          return true;
        },
      );

      expect(
        await service.followWork('../auth/login'),
        AccountSyncOutcome.failed,
      );
      expect(validated, isFalse);
      expect(called, isFalse);
    });
  });
}
