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

    test('ログイン済み作品ページからremoteの最終episode IDを読む', () async {
      Uri? capturedUrl;
      String? capturedCookie;
      final service = KakuyomuReadingProgressService(
        sessionRepository: _FakeSessionRepository('session=test'),
        remoteStateFetcher: (url, cookieHeader) async {
          capturedUrl = url;
          capturedCookie = cookieHeader;
          return KakuyomuRemoteReadingStateHttpResponse(
            statusCode: 200,
            realUri: url,
            body: '''
              <html><body>
                <script id="__NEXT_DATA__" type="application/json">
                  {
                    "props": {
                      "pageProps": {
                        "__APOLLO_STATE__": {
                          "Work:$workId": {
                            "__typename": "Work",
                            "id": "$workId",
                            "visitorReadingHistory": {
                              "__ref": "ReadingHistory:visitor/$workId"
                            }
                          },
                          "ReadingHistory:visitor/$workId": {
                            "__typename": "ReadingHistory",
                            "id": "visitor/$workId",
                            "episodeUnion": {
                              "__ref": "Episode:$episodeId"
                            }
                          },
                          "Episode:$episodeId": {
                            "__typename": "Episode",
                            "id": "$episodeId"
                          }
                        }
                      }
                    }
                  }
                </script>
              </body></html>
            ''',
          );
        },
      );

      final state = await service.fetchRemoteState(workId);

      expect(state.isAvailable, isTrue);
      expect(state.episodeId, episodeId);
      expect(capturedUrl?.toString(), 'https://kakuyomu.jp/works/$workId');
      expect(capturedCookie, 'session=test');
    });

    test('visitorReadingHistoryがnullなら取得成功かつ履歴なしを返す', () async {
      final service = KakuyomuReadingProgressService(
        sessionRepository: _FakeSessionRepository('session=test'),
        remoteStateFetcher: (url, cookieHeader) async {
          return KakuyomuRemoteReadingStateHttpResponse(
            statusCode: 200,
            realUri: url,
            body: '''
              <script id="__NEXT_DATA__" type="application/json">
                {
                  "props": {
                    "pageProps": {
                      "__APOLLO_STATE__": {
                        "Work:$workId": {
                          "id": "$workId",
                          "visitorReadingHistory": null
                        }
                      }
                    }
                  }
                }
              </script>
            ''',
          );
        },
      );

      final state = await service.fetchRemoteState(workId);

      expect(state.isAvailable, isTrue);
      expect(state.episodeId, isNull);
    });

    test('remote履歴取得失敗は履歴なしと区別してunavailableを返す', () async {
      final service = KakuyomuReadingProgressService(
        sessionRepository: _FakeSessionRepository('session=test'),
        remoteStateFetcher: (url, cookieHeader) async {
          return KakuyomuRemoteReadingStateHttpResponse(
            statusCode: 503,
            realUri: url,
            body: 'maintenance',
          );
        },
      );

      final state = await service.fetchRemoteState(workId);

      expect(state.isAvailable, isFalse);
      expect(state.episodeId, isNull);
    });

    test('remote履歴のApollo構造が不正ならunavailableを返す', () async {
      final service = KakuyomuReadingProgressService(
        sessionRepository: _FakeSessionRepository('session=test'),
        remoteStateFetcher: (url, cookieHeader) async {
          return KakuyomuRemoteReadingStateHttpResponse(
            statusCode: 200,
            realUri: url,
            body: '''
              <script id="__NEXT_DATA__" type="application/json">
                {"props":{"pageProps":{"__APOLLO_STATE__":{}}}}
              </script>
            ''',
          );
        },
      );

      final state = await service.fetchRemoteState(workId);

      expect(state.isAvailable, isFalse);
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

    test('Cookieが無ければremote履歴も取得しない', () async {
      var called = false;
      final service = KakuyomuReadingProgressService(
        sessionRepository: _FakeSessionRepository(null),
        remoteStateFetcher: (url, cookieHeader) async {
          called = true;
          return KakuyomuRemoteReadingStateHttpResponse(
            statusCode: 200,
            realUri: url,
          );
        },
      );

      final state = await service.fetchRemoteState(workId);

      expect(state.isAvailable, isFalse);
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
