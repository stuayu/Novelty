import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/utils/estar_uri.dart';

void main() {
  group('Estar URI', () {
    test('数字の作品IDから作品URLを組み立てる', () {
      expect(
        buildEstarWorkUrl('26544596'),
        'https://estar.jp/novels/26544596',
      );
    });

    test('作品IDと開始ページから本文URLを組み立てる', () {
      expect(
        buildEstarEpisodeUrl('26544596', 3),
        'https://estar.jp/novels/26544596/viewer?page=3',
      );
    });

    test('作品URLと本文URLから数字の作品IDを抽出する', () {
      expect(extractEstarWorkId('https://estar.jp/novels/594'), '594');
      expect(
        extractEstarWorkId(
          'https://estar.jp/novels/26544596/viewer/?page=3',
        ),
        '26544596',
      );
    });

    test('本文URLから開始ページを抽出する', () {
      expect(
        extractEstarEpisodePageNo(
          'https://estar.jp/novels/26544596/viewer?page=13',
        ),
        13,
      );
    });

    test('非数字ID・不正ページ・公式外URLを拒否する', () {
      expect(() => buildEstarWorkUrl('12-34'), throwsFormatException);
      expect(
        () => buildEstarEpisodeUrl('26544596', 0),
        throwsArgumentError,
      );
      expect(
        () => extractEstarWorkId('https://example.com/novels/26544596'),
        throwsFormatException,
      );
      expect(
        () => extractEstarWorkId('https://estar.jp/users/26544596'),
        throwsFormatException,
      );
      expect(
        () => extractEstarEpisodePageNo(
          'https://estar.jp/novels/26544596/viewer?page=x',
        ),
        throwsFormatException,
      );
    });
  });
}
