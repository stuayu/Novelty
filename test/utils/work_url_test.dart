import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:novelty/utils/work_url.dart';

void main() {
  group('buildWorkUrl', () {
    test('なろうはncodeを正規化して作品URLを組み立てる', () {
      expect(
        buildWorkUrl(NovelSource.narou, ncode: 'N1234AB'),
        'https://ncode.syosetu.com/n1234ab/',
      );
    });

    test('カクヨムはworkIdで作品URLを組み立てる', () {
      expect(
        buildWorkUrl(
          NovelSource.kakuyomu,
          workId: '16818023211929539879',
        ),
        'https://kakuyomu.jp/works/16818023211929539879',
      );
    });

    test('なろうはncodeがnullでもクラッシュしない（空URL）', () {
      expect(
        buildWorkUrl(NovelSource.narou),
        'https://ncode.syosetu.com//',
      );
    });

    test('カクヨムはworkIdがnullでもクラッシュしない', () {
      expect(
        buildWorkUrl(NovelSource.kakuyomu),
        'https://kakuyomu.jp/works/',
      );
    });

    test('アルファポリスは複合workIdから作品URLを組み立てる', () {
      expect(
        buildWorkUrl(
          NovelSource.alphapolis,
          workId: '480761512-519070183',
        ),
        'https://www.alphapolis.co.jp/novel/480761512/519070183',
      );
    });

    test('アルファポリスはworkIdがnullならFormatExceptionを投げる', () {
      expect(
        () => buildWorkUrl(NovelSource.alphapolis),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
