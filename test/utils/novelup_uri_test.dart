import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/utils/novelup_uri.dart';

void main() {
  group('Novelup URI', () {
    test('数字の作品IDから作品URLを組み立てる', () {
      expect(
        buildNovelupWorkUrl('258567814'),
        'https://novelup.plus/story/258567814',
      );
    });

    test('作品IDとサイト固有エピソードIDから本文URLを組み立てる', () {
      expect(
        buildNovelupEpisodeUrl('258567814', '492921017'),
        'https://novelup.plus/story/258567814/492921017',
      );
    });

    test('作品URLと本文URLから作品IDを抽出する', () {
      expect(
        extractNovelupWorkId('https://novelup.plus/story/258567814'),
        '258567814',
      );
      expect(
        extractNovelupWorkId(
          'https://novelup.plus/story/258567814/492921017',
        ),
        '258567814',
      );
    });

    test('本文URLからサイト固有エピソードIDを抽出する', () {
      expect(
        extractNovelupEpisodeId(
          'https://novelup.plus/story/258567814/492921017',
        ),
        '492921017',
      );
    });

    test('非数字ID・作品URLからの話ID抽出・公式外URLを拒否する', () {
      expect(() => buildNovelupWorkUrl('12-34'), throwsFormatException);
      expect(
        () => buildNovelupEpisodeUrl('258567814', 'first'),
        throwsFormatException,
      );
      expect(
        () => extractNovelupEpisodeId(
          'https://novelup.plus/story/258567814',
        ),
        throwsFormatException,
      );
      expect(
        () => extractNovelupWorkId(
          'https://example.com/story/258567814',
        ),
        throwsFormatException,
      );
    });
  });
}
