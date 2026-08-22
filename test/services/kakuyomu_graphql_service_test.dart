import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/repositories/kakuyomu_session_repository.dart';
import 'package:novelty/services/kakuyomu_graphql_service.dart';

class _FakeSessionRepository extends KakuyomuSessionRepository {
  _FakeSessionRepository(this.cookieHeader);

  final String? cookieHeader;

  @override
  Future<String?> buildCookieHeader() async => cookieHeader;
}

void main() {
  group('KakuyomuGraphqlService', () {
    test('公開operationではCookie無しでtransportへ渡す', () async {
      KakuyomuGraphqlRequest? captured;
      final service = KakuyomuGraphqlService(
        sessionRepository: _FakeSessionRepository(null),
        transport: (request) async {
          captured = request;
          return const KakuyomuGraphqlResponse(
            statusCode: 200,
            body: <String, Object?>{
              'data': <String, Object?>{'work': <String, Object?>{'id': '1'}},
            },
          );
        },
      );

      final response = await service.execute(
        operationName: 'GetWorkPage',
        query: 'query GetWorkPage { work { id } }',
        variables: const <String, Object?>{'workId': '1'},
      );

      expect(captured?.operationName, 'GetWorkPage');
      expect(captured?.variables, const <String, Object?>{'workId': '1'});
      expect(captured?.cookieHeader, isNull);
      expect(response?.statusCode, 200);
      expect(response?.hasErrors, isFalse);
      expect(response?.data?['work'], isA<Map<Object?, Object?>>());
    });

    test('認証operationでは保存済みCookieをtransportへ渡す', () async {
      KakuyomuGraphqlRequest? captured;
      final service = KakuyomuGraphqlService(
        sessionRepository: _FakeSessionRepository('session=test'),
        transport: (request) async {
          captured = request;
          return const KakuyomuGraphqlResponse(
            statusCode: 200,
            body: <String, Object?>{'data': <String, Object?>{}},
          );
        },
      );

      await service.execute(
        operationName: 'AuthenticatedOperation',
        query: 'query AuthenticatedOperation { visitor { id } }',
        authenticated: true,
      );

      expect(captured?.cookieHeader, 'session=test');
    });

    test('認証operationでCookieが無ければHTTP通信しない', () async {
      var called = false;
      final service = KakuyomuGraphqlService(
        sessionRepository: _FakeSessionRepository(null),
        transport: (request) async {
          called = true;
          return const KakuyomuGraphqlResponse(
            statusCode: 200,
            body: <String, Object?>{},
          );
        },
      );

      final response = await service.execute(
        operationName: 'AuthenticatedOperation',
        query: 'query AuthenticatedOperation { visitor { id } }',
        authenticated: true,
      );

      expect(response, isNull);
      expect(called, isFalse);
    });

    test('GraphQL errorsを成功扱いしないため検出できる', () async {
      final service = KakuyomuGraphqlService(
        sessionRepository: _FakeSessionRepository(null),
        transport: (request) async {
          return const KakuyomuGraphqlResponse(
            statusCode: 200,
            body: <String, Object?>{
              'errors': <Object?>[
                <String, Object?>{'message': 'failed'},
              ],
            },
          );
        },
      );

      final response = await service.execute(
        operationName: 'BrokenOperation',
        query: 'query BrokenOperation { unknown }',
      );

      expect(response?.hasErrors, isTrue);
      expect(response?.data, isNull);
    });
  });
}
