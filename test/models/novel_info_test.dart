import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/database/database.dart';
import 'package:novelty/models/novel_info.dart';
import 'package:novelty/models/novel_info_extension.dart';
import 'package:novelty/sites/novel_source.dart';

void main() {
  group('NovelInfo', () {
    test('fromJsonでJSONからインスタンスを生成できる', () {
      final json = {
        'title': 'Test Novel',
        'ncode': 'N1234AB',
        'writer': 'Author',
        'userid': '12345',
        'novel_type': '1',
        'end': '0',
        'general_all_no': '100',
        'genre': '1',
        'global_point': '10000',
      };

      final novel = NovelInfo.fromJson(json);

      expect(novel.title, equals('Test Novel'));
      expect(novel.workId, equals('n1234ab'));
      expect(novel.userId, equals(12345));
      expect(novel.novelType, equals(1));
      expect(novel.globalPoint, equals(10000));
    });

    test('genreが数値で返る作品でもgenreIdを文字列としてパースできる', () {
      // なろうAPIは作品によってgenreを数値（int）で返す場合がある
      final json = {
        'title': 'Test Novel',
        'ncode': 'N1234AB',
        'novel_type': '1',
        'end': '0',
        'genre': 201,
      };

      final novel = NovelInfo.fromJson(json);

      expect(novel.genreId, equals('201'));
    });

    test('toJsonでJSONに変換できる', () {
      const novel = NovelInfo(
        title: 'Test Novel',
        ncode: 'n1234',
        novelType: 1,
      );

      final json = novel.toJson();

      expect(json['title'], equals('Test Novel'));
      expect(json['ncode'], equals('n1234'));
    });

    test('toDbCompanionが正しく動作する', () {
      const novel = NovelInfo(
        ncode: 'n1234',
        title: 'Test Novel',
        writer: 'Author',
        userId: 12345,
        novelType: 1,
        end: 0,
        genreId: '1',
        generalAllNo: 100,
      );

      final companion = novel.toDbCompanion();

      expect(companion.workId.value, equals('n1234'));
      expect(companion.title.value, equals('Test Novel'));
      expect(companion.userId.value, equals(12345));
    });

    test('掲載日時をソート可能な整数としてDBへ保存する', () {
      const novel = NovelInfo(
        ncode: 'n1234',
        generalFirstup: '2026-07-01 12:34:56',
        generalLastup: '2026-07-12 23:45:01',
      );

      final companion = novel.toDbCompanion();

      expect(companion.generalFirstup.value, 20260701123456);
      expect(companion.generalLastup.value, 20260712234501);
    });

    test('DBの掲載日時をAPIと同じ文字列形式へ復元する', () {
      const dbNovel = Novel(
        source: NovelSource.narou,
        workId: 'n1234',
        generalFirstup: 20260701123456,
        generalLastup: 20260712234501,
        isPrivate: false,
      );

      final model = dbNovel.toModel();

      expect(model.generalFirstup, '2026-07-01 12:34:56');
      expect(model.generalLastup, '2026-07-12 23:45:01');
    });

    test('作品更新日時の文字列を数値へ変換する', () {
      final novel = NovelInfo.fromJson({
        'ncode': 'N1234AB',
        'novelupdated_at': '2026-07-12 23:45:01',
        'updated_at': '2026-07-12 23:46:02',
      });

      expect(novel.novelupdatedAt, 20260712234501);
      expect(novel.updatedAt, 20260712234602);
    });
  });
}
