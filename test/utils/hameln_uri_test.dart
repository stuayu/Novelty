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
    });
  });
}
