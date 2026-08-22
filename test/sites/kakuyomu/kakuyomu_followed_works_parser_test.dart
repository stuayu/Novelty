import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/sites/kakuyomu/kakuyomu_followed_works_parser.dart';

void main() {
  final parser = KakuyomuFollowedWorksParser();
  final baseUri = Uri.parse(
    'https://kakuyomu.jp/my/antenna/works/all?order=last_read_at',
  );

  String fixture(String name) =>
      File('test/fixtures/kakuyomu/$name').readAsStringSync();

  test('通常ページから作品IDとタイトルと次ページを抽出する', () {
    final result = parser.parse(
      fixture('followed_works_page.html'),
      baseUri: baseUri,
    );

    expect(result.entries, hasLength(2));
    expect(result.entries[0].workId, '1177354054880000001');
    expect(result.entries[0].title, 'テスト作品 1');
    expect(result.entries[1].workId, '1177354054880000002');
    expect(result.entries[1].title, 'テスト作品 2');
    expect(
      result.nextPageUrl.toString(),
      'https://kakuyomu.jp/my/antenna/works/all?page=2&order=last_read_at',
    );
  });

  test('空ページは0件かつ次ページなし', () {
    final result = parser.parse(
      fixture('followed_works_empty.html'),
      baseUri: baseUri,
    );

    expect(result.entries, isEmpty);
    expect(result.nextPageUrl, isNull);
  });

  test('作品IDが無い行と外部サイトの作品風リンクを無視する', () {
    final result = parser.parse(
      fixture('followed_works_broken.html'),
      baseUri: baseUri,
    );

    expect(result.entries, isEmpty);
  });

  test('同一作品が複数リンクに含まれても1件だけ返す', () {
    const html = '''
      <ul>
        <li class="widget-antennaList-item">
          <h4 class="widget-antennaList-title">
            <a href="/works/1177354054880000001">作品</a>
          </h4>
          <a href="/works/1177354054880000001/episodes/1">続きを読む</a>
        </li>
      </ul>
    ''';

    final result = parser.parse(html, baseUri: baseUri);
    expect(result.entries, hasLength(1));
  });
}
