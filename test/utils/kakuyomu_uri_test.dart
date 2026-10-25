import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/utils/kakuyomu_uri.dart';

void main() {
  group('shouldShowKakuyomuLoginCheckError', () {
    test('ログイン送信後の完了先ではログイン確認エラーを表示する', () {
      expect(
        shouldShowKakuyomuLoginCheckError(
          loginAttempted: true,
          pagePath: '/',
        ),
        isTrue,
      );
      expect(
        shouldShowKakuyomuLoginCheckError(
          loginAttempted: true,
          pagePath: '/works/123',
        ),
        isTrue,
      );
    });

    test('認証・登録・パスワード再設定の画面ではエラーを表示しない', () {
      for (final path in [
        '/auth/login',
        '/signup',
        '/users/sign_up',
        '/password/reset',
      ]) {
        expect(
          shouldShowKakuyomuLoginCheckError(
            loginAttempted: true,
            pagePath: path,
          ),
          isFalse,
        );
      }
    });

    test('未ログイン状態でトップへ進んでも確認エラーを表示しない', () {
      expect(
        shouldShowKakuyomuLoginCheckError(
          loginAttempted: false,
          pagePath: '/',
        ),
        isFalse,
      );
    });
  });

  group('shouldCheckKakuyomuLoginAfterNavigation', () {
    test('トップへの遷移は送信状態に関わらずセッション確認する', () {
      expect(
        shouldCheckKakuyomuLoginAfterNavigation('/'),
        isTrue,
      );
      expect(
        shouldCheckKakuyomuLoginAfterNavigation('/works/123'),
        isTrue,
      );
      expect(
        shouldCheckKakuyomuLoginAfterNavigation('/signup'),
        isFalse,
      );
    });
  });

  group('shouldResetKakuyomuLoginAttempt', () {
    test('認証フォームへ戻ったときだけ送信フラグをリセットする', () {
      expect(shouldResetKakuyomuLoginAttempt('/auth/login'), isTrue);
      expect(shouldResetKakuyomuLoginAttempt('/login'), isTrue);
      expect(shouldResetKakuyomuLoginAttempt('/auth/two_factor'), isFalse);
      expect(shouldResetKakuyomuLoginAttempt('/'), isFalse);
    });
  });

  group('isTrustedKakuyomuUri', () {
    test('HTTPSのkakuyomu.jpだけを許可する', () {
      expect(
        isTrustedKakuyomuUri(Uri.parse('https://kakuyomu.jp/my')),
        isTrue,
      );
      expect(
        isTrustedKakuyomuUri(Uri.parse('https://kakuyomu.jp/auth/login')),
        isTrue,
      );
    });

    test('紛らわしい外部ホストとHTTPを拒否する', () {
      expect(
        isTrustedKakuyomuUri(Uri.parse('https://evilkakuyomu.jp/my')),
        isFalse,
      );
      expect(
        isTrustedKakuyomuUri(Uri.parse('https://kakuyomu.jp.example.com/my')),
        isFalse,
      );
      expect(
        isTrustedKakuyomuUri(Uri.parse('https://sub.kakuyomu.jp/my')),
        isFalse,
      );
      expect(
        isTrustedKakuyomuUri(Uri.parse('http://kakuyomu.jp/my')),
        isFalse,
      );
      expect(
        isTrustedKakuyomuUri(Uri.parse('https://kakuyomu.jp:8443/my')),
        isFalse,
      );
      expect(
        isTrustedKakuyomuUri(Uri.parse('https://user@kakuyomu.jp/my')),
        isFalse,
      );
    });
  });

  group('extractKakuyomuEpisodeId', () {
    const workId = '1177354054880000001';
    const episodeId = '1177354054881000001';

    test('公式の絶対URLからepisode IDを取得する', () {
      expect(
        extractKakuyomuEpisodeId(
          workId: workId,
          url: 'https://kakuyomu.jp/works/$workId/episodes/$episodeId',
        ),
        episodeId,
      );
    });

    test('保存済み相対URLからepisode IDを取得する', () {
      expect(
        extractKakuyomuEpisodeId(
          workId: workId,
          url: '/works/$workId/episodes/$episodeId',
        ),
        episodeId,
      );
    });

    test('別作品・外部ホスト・非HTTPS・非数値IDを拒否する', () {
      expect(
        extractKakuyomuEpisodeId(
          workId: workId,
          url: 'https://kakuyomu.jp/works/999/episodes/$episodeId',
        ),
        isNull,
      );
      expect(
        extractKakuyomuEpisodeId(
          workId: workId,
          url: 'https://example.com/works/$workId/episodes/$episodeId',
        ),
        isNull,
      );
      expect(
        extractKakuyomuEpisodeId(
          workId: workId,
          url: 'http://kakuyomu.jp/works/$workId/episodes/$episodeId',
        ),
        isNull,
      );
      expect(
        extractKakuyomuEpisodeId(
          workId: workId,
          url: 'https://kakuyomu.jp/works/$workId/episodes/not-a-number',
        ),
        isNull,
      );
    });
  });
}
