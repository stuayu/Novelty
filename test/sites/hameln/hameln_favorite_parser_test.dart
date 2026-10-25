import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/sites/hameln/hameln_favorite_parser.dart';
import 'package:novelty/sites/novel_source.dart';

void main() {
  String fixture(String name) =>
      File('test/fixtures/hameln/$name').readAsStringSync();

  group('HamelnFavoriteParser', () {
    const parser = HamelnFavoriteParser();

    test('お気に入り一覧から作品ID・タイトル・作者を読み取る', () {
      final result = parser.parse(fixture('favorites.html'));

      expect(result, hasLength(1));
      expect(result.single.source, NovelSource.hameln);
      expect(result.single.workId, '429419');
      expect(result.single.title, '機械仕掛けの竜と相棒の物語');
      expect(result.single.writer, '作者名');
    });

    test('空のお気に入りフォームを空一覧として扱う', () {
      expect(parser.parse('<form id="favo_list"></form>'), isEmpty);
    });

    test('お気に入り一覧以外のページは同期成功として扱わない', () {
      expect(
        () => parser.parse('<html><title>ログイン</title></html>'),
        throwsFormatException,
      );
    });

    test('公式サイト外や作品URL以外のリンクは取り込まない', () {
      final result = parser.parse('''
        <div id="favo_list">
          <div id="favo-id999">
            <a href="https://example.com/novel/999/">外部</a>
          </div>
          <div id="favo-id1000">
            <a href="/?mode=favo">お気に入り</a>
          </div>
        </div>
      ''');

      expect(result, isEmpty);
    });

    test('同じ作品を重複して返さない', () {
      final result = parser.parse('''
        <div id="favo_list">
          <div id="favo-id429419">
            <a href="https://syosetu.org/novel/429419/">作品</a>
            <a href="/user/123/">作者</a>
          </div>
          <div id="favo-id429419-copy">
            <a href="/novel/429419/">作品</a>
            <a href="/user/123/">作者</a>
          </div>
        </div>
      ''');

      expect(result, hasLength(1));
    });
  });
}
