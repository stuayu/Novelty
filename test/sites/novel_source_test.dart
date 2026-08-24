import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/providers/site_rate_limiter_provider.dart';
import 'package:novelty/sites/novel_source.dart';

void main() {
  group('NovelSource', () {
    test('定義されているサイト種別は5つ', () {
      expect(NovelSource.values, hasLength(5));
      expect(
        NovelSource.values.map((source) => source.name),
        containsAll(<String>[
          'narou',
          'kakuyomu',
          'alphapolis',
          'hameln',
          'estar',
        ]),
      );
    });

    test('narou のメタデータが仕様どおり', () {
      const source = NovelSource.narou;

      expect(source.dbId, 'narou');
      expect(source.label, '小説家になろう');
      expect(source.baseUrl, 'https://ncode.syosetu.com');
    });

    test('kakuyomu のメタデータが仕様どおり', () {
      const source = NovelSource.kakuyomu;

      expect(source.dbId, 'kakuyomu');
      expect(source.label, 'カクヨム');
      expect(source.baseUrl, 'https://kakuyomu.jp');
    });

    test('alphapolis のメタデータが仕様どおり', () {
      const source = NovelSource.alphapolis;

      expect(source.dbId, 'alphapolis');
      expect(source.label, 'アルファポリス');
      expect(source.baseUrl, 'https://www.alphapolis.co.jp');
    });

    test('hameln のメタデータが仕様どおり', () {
      const source = NovelSource.hameln;

      expect(source.dbId, 'hameln');
      expect(source.label, 'ハーメルン');
      expect(source.baseUrl, 'https://syosetu.org');
    });

    test('estar のメタデータと取得間隔が仕様どおり', () {
      const source = NovelSource.estar;

      expect(source.dbId, 'estar');
      expect(source.label, 'エブリスタ');
      expect(source.baseUrl, 'https://estar.jp');
      expect(siteRequestIntervals[source], const Duration(seconds: 1));
    });

    test('dbId は enum 名と同一', () {
      for (final source in NovelSource.values) {
        expect(source.dbId, source.name);
      }
    });

    test('dbId はサイト間で重複しない', () {
      final dbIds = NovelSource.values.map((source) => source.dbId).toSet();

      expect(dbIds, hasLength(NovelSource.values.length));
    });

    test('values.byName() で dbId からインスタンスを復元できる', () {
      for (final source in NovelSource.values) {
        expect(NovelSource.values.byName(source.dbId), source);
      }
    });
  });
}
