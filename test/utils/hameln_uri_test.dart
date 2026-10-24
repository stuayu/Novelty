import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/utils/hameln_uri.dart';

void main() {
  group('ハーメルンURL', () {
    test('数字の作品IDから作品URLを組み立てる', () {
      expect(
        buildHamelnWorkUrl('328453'),
        'https://syosetu.org/novel/328453/',
      );
    });

    test('作品IDとサイト固有話数からエピソードURLを組み立てる', () {
      expect(
        buildHamelnEpisodeUrl('328453', '3'),
        'https://syosetu.org/novel/328453/3.html',
      );
    });

    test('作品URLとエピソードURLから作品IDを抽出する', () {
      expect(
        extractHamelnWorkId('https://syosetu.org/novel/328453/'),
        '328453',
      );
      expect(
        extractHamelnWorkId('https://syosetu.org/novel/328453/3.html'),
        '328453',
      );
    });

    test('エピソードURLからサイト固有話数を抽出する', () {
      expect(
        extractHamelnEpisodeNumber(
          'https://syosetu.org/novel/328453/3.html',
        ),
        '3',
      );
      expect(
        () => extractHamelnEpisodeNumber(
          'https://syosetu.org/novel/328453/',
        ),
        throwsFormatException,
      );
    });

    test('数字以外のIDと公式外URLを拒否する', () {
      expect(() => buildHamelnWorkUrl('abc'), throwsFormatException);
      expect(
        () => buildHamelnEpisodeUrl('328453', 'first'),
        throwsFormatException,
      );
      expect(
        () => extractHamelnWorkId('https://example.com/novel/328453/'),
        throwsFormatException,
      );
      expect(
        () => extractHamelnWorkId('https://syosetu.org:8443/novel/328453/'),
        throwsFormatException,
      );
      expect(
        () => extractHamelnWorkId('https://user@syosetu.org/novel/328453/'),
        throwsFormatException,
      );
    });

    test('WebView遷移を公式HTTPS originかつrobots許可URLに限定する', () {
      expect(
        isAllowedHamelnNavigationUri(
          Uri.parse('https://syosetu.org/novel/328453/'),
        ),
        isTrue,
      );
      expect(
        isAllowedHamelnNavigationUri(
          Uri.parse('https://h.syosetu.org/novel/328453/'),
        ),
        isTrue,
      );
      expect(
        isAllowedHamelnNavigationUri(
          Uri.parse('http://syosetu.org/novel/328453/'),
        ),
        isFalse,
      );
      expect(
        isAllowedHamelnNavigationUri(
          Uri.parse('https://example.com/novel/328453/'),
        ),
        isFalse,
      );
      expect(
        isAllowedHamelnNavigationUri(
          Uri.parse('https://syosetu.org/novel/328453/?mode=ss_detail3'),
        ),
        isFalse,
      );
      expect(isAllowedHamelnNavigationUri(null), isFalse);
    });

    test('robots.txtで禁止された動作URLを拒否する', () {
      for (final uri in <Uri>[
        Uri.parse('https://syosetu.org/conv/pdf/328453/'),
        Uri.parse('https://syosetu.org/?mode=ss_detail3'),
        Uri.parse('https://syosetu.org/?mode=seek_list'),
      ]) {
        expect(isHamelnRobotsDisallowedUri(uri), isTrue);
        expect(isAllowedHamelnNavigationUri(uri), isFalse);
      }
      expect(
        isHamelnRobotsDisallowedUri(
          Uri.parse('https://syosetu.org/novel/328453/'),
        ),
        isFalse,
      );
    });

    test('WebViewはCloudflare challenge用の安全なサブフレームを許可する', () {
      for (final uri in <Uri>[
        Uri.parse('about:blank'),
        Uri.parse('about:srcdoc'),
        Uri.parse(
          'https://challenges.cloudflare.com/cdn-cgi/challenge-platform/',
        ),
        Uri.parse('https://syosetu.org/novel/328453/'),
      ]) {
        expect(isAllowedHamelnSubframeNavigationUri(uri), isTrue);
      }
      expect(
        isAllowedHamelnSubframeNavigationUri(
          Uri.parse('https://example.com/tracker'),
        ),
        isFalse,
      );
      expect(
        isAllowedHamelnSubframeNavigationUri(
          Uri.parse('https://syosetu.org/?mode=ss_detail3'),
        ),
        isFalse,
      );
      expect(isAllowedHamelnSubframeNavigationUri(null), isFalse);
    });
  });
}
