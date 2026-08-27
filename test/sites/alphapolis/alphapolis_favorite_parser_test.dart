import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/sites/alphapolis/alphapolis_favorite_parser.dart';
import 'package:novelty/sites/novel_source.dart';

void main() {
  String fixture(String name) =>
      File('test/fixtures/alphapolis/$name').readAsStringSync();

  /// 一覧JSONを埋め込んだ最小HTMLを組み立てる。
  String embedJson(String body) =>
      '<div id="app-favorite-content">'
      ' <script type="application/json">$body</script></div>';

  group('AlphapolisFavoriteParser', () {
    final parser = AlphapolisFavoriteParser();

    test('埋め込みJSONから作品とページ情報を取り出す', () {
      final page = parser.parse(fixture('favorite_novel_page1.html'));

      expect(page.currentPage, 1);
      expect(page.lastPage, 2);
      expect(page.entries.length, 2);

      final first = page.entries.first;
      expect(first.source, NovelSource.alphapolis);
      expect(first.workId, '78147770-288151080');
      expect(first.title, '最初の作品');
      expect(first.writer, '作者A');
    });

    test('タイトルの連続空白を1つに詰める', () {
      final page = parser.parse(fixture('favorite_novel_page1.html'));

      expect(page.entries[1].title, '空白を含む タイトル');
    });

    test('小説以外のURLは取り込まない', () {
      final page = parser.parse(fixture('favorite_novel_page1.html'));

      expect(
        page.entries.map((entry) => entry.workId),
        isNot(contains(contains('12345'))),
      );
    });

    test('最終ページを解析できる', () {
      final page = parser.parse(fixture('favorite_novel_page2.html'));

      expect(page.currentPage, 2);
      expect(page.lastPage, 2);
      expect(page.entries.single.workId, '784290940-355109340');
    });

    test('JSONが無ければFormatException', () {
      expect(
        () => parser.parse('<html><body>お気に入り</body></html>'),
        throwsFormatException,
      );
    });

    test('paginatorが無ければFormatException', () {
      final html = embedJson('{"viewName":"お気に入り小説"}');

      expect(() => parser.parse(html), throwsFormatException);
    });

    test('itemsが空でも空の結果を返す', () {
      final html = embedJson(
        '{"paginator":{"currentPage":1,"lastPage":1,"items":[]}}',
      );

      final page = parser.parse(html);

      expect(page.entries, isEmpty);
      expect(page.lastPage, 1);
    });
  });
}
