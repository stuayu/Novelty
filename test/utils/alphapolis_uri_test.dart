import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/utils/alphapolis_uri.dart';

void main() {
  group('AlphapolisUri', () {
    test('authorIdとサイト側workIdからアプリ内workIdを組み立てる', () {
      expect(
        buildAlphapolisWorkId('480761512', '519070183'),
        '480761512-519070183',
      );
    });

    test('アプリ内workIdをauthorIdとサイト側workIdへ分解する', () {
      final parts = splitAlphapolisWorkId('480761512-519070183');

      expect(parts.authorId, '480761512');
      expect(parts.siteWorkId, '519070183');
    });

    test('アプリ内workIdから作品URLを組み立てる', () {
      expect(
        buildAlphapolisWorkUrl('480761512-519070183'),
        'https://www.alphapolis.co.jp/novel/480761512/519070183',
      );
    });

    test('数字2要素でないIDはFormatExceptionを投げる', () {
      for (final invalid in <String>[
        '',
        '480761512',
        '480761512-',
        '-519070183',
        '480761512-519070183-extra',
        'author-519070183',
      ]) {
        expect(
          () => splitAlphapolisWorkId(invalid),
          throwsA(isA<FormatException>()),
          reason: invalid,
        );
      }
    });
  });
}
