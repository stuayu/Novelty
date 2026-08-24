import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/repositories/kakuyomu_session_repository.dart';
import 'package:novelty/sites/kakuyomu/kakuyomu_history_client.dart';
import 'package:novelty/sites/kakuyomu/kakuyomu_history_parser.dart';
import 'package:novelty/sites/novel_source.dart';

class _FakeSessionRepository extends KakuyomuSessionRepository {
  _FakeSessionRepository(this.cookieHeader);

  final String? cookieHeader;

  @override
  Future<String?> buildCookieHeader() async => cookieHeader;
}

void main() {
  const workId = '1177354054880000001';
  const episodeId = '1177354054881000001';

  const authenticatedHtml =
      '''
<html data-is-guest="0"><body>
  <ul class="widget-antennaList">
    <li class="widget-antennaList-item">
      <a class="widget-antennaList-workInfo" href="/works/$workId">
        <h4 class="widget-antennaList-title">テスト作品</h4>
        <ul class="widget-antennaList-event"><li>8月23日閲覧</li></ul>
      </a>
      <a class="widget-antennaList-continueReading"
         href="/works/$workId/resume_reading">読む</a>
    </li>
  </ul>
</body></html>
''';

  test('閲覧履歴行から作品・episode・最終閲覧日時を抽出する', () {
    final page = KakuyomuHistoryParser().parse(
      authenticatedHtml,
      baseUri: Uri.parse('https://kakuyomu.jp/my/antenna/reading_histories'),
      now: DateTime(2026, 8, 23),
    );

    expect(page.isGuestPage, isFalse);
    expect(page.entries, hasLength(1));
    final entry = page.entries.single;
    expect(entry.source, NovelSource.kakuyomu);
    expect(entry.workId, workId);
    expect(entry.episodeId, isNull);
    expect(entry.resumeReadingUrl?.path, '/works/$workId/resume_reading');
    expect(entry.title, 'テスト作品');
    expect(entry.episodeTitle, '読む');
    expect(entry.lastReadAt, DateTime(2026, 8, 23));
  });

  test('実取得HTMLのguest判定マーカーをセッション切れとして扱う', () {
    final page = KakuyomuHistoryParser().parse(
      '''
<html lang="ja" data-route="public:my:antenna:reading_histories.guest"
  data-is-guest="1">
  <body id="page-my-antenna-readingHistoriesGuest">
    <a href="/auth/login?location=%2Fmy%2Fantenna%2Freading_histories">ログイン</a>
  </body>
</html>
''',
      baseUri: Uri.parse('https://kakuyomu.jp/my/antenna/reading_histories'),
    );

    expect(page.isGuestPage, isTrue);
    expect(page.entries, isEmpty);
  });

  test('ClientはCookieを付けて履歴を取得する', () async {
    Uri? capturedUrl;
    String? capturedCookie;
    final client = KakuyomuHistoryClient(
      sessionRepository: _FakeSessionRepository('session=test'),
      pageFetcher: (url, cookieHeader) async {
        capturedUrl = url;
        capturedCookie = cookieHeader;
        if (url.path.endsWith('/resume_reading')) {
          return KakuyomuHistoryHttpResponse(
            statusCode: 200,
            realUri: Uri.parse(
              'https://kakuyomu.jp/works/$workId/episodes/$episodeId',
            ),
            body: '<html></html>',
          );
        }
        return KakuyomuHistoryHttpResponse(
          statusCode: 200,
          realUri: url,
          body: authenticatedHtml,
        );
      },
    );

    final entries = await client.fetchAll();

    expect(capturedUrl?.path, '/works/$workId/resume_reading');
    expect(capturedCookie, 'session=test');
    expect(entries.single.workId, workId);
    expect(entries.single.episodeId, episodeId);
  });

  test('Clientはguestページをセッション切れとして返す', () async {
    final client = KakuyomuHistoryClient(
      sessionRepository: _FakeSessionRepository('session=test'),
      pageFetcher: (url, cookieHeader) async => KakuyomuHistoryHttpResponse(
        statusCode: 200,
        realUri: url,
        body: '<body id="page-my-antenna-readingHistoriesGuest"></body>',
      ),
    );

    await expectLater(
      client.fetchAll(),
      throwsA(isA<KakuyomuSessionExpiredException>()),
    );
  });
}
