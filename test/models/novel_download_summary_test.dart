import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/models/novel_download_summary.dart';
import 'package:novelty/sites/novel_source.dart';

void main() {
  group('NovelDownloadSummary', () {
    const base = NovelDownloadSummary(
      source: NovelSource.alphapolis,
      workId: '123456789',
      successCount: 5,
      failureCount: 1,
      totalEpisodes: 10,
    );

    test('作品をsourceとworkIdの組で識別する', () {
      expect(base.source, NovelSource.alphapolis);
      expect(base.workId, '123456789');
    });

    test('copyWithでフィールドを変更できる', () {
      final updated = base.copyWith(
        source: NovelSource.kakuyomu,
        workId: '16818023211929539879',
        successCount: 8,
        failureCount: 0,
      );

      expect(updated.source, NovelSource.kakuyomu);
      expect(updated.workId, '16818023211929539879');
      expect(updated.successCount, 8);
      expect(updated.failureCount, 0);
      expect(updated.totalEpisodes, 10);
    });

    test('isCompleteは全話成功時だけtrueを返す', () {
      expect(
        base.copyWith(successCount: 10, failureCount: 0).isComplete,
        isTrue,
      );
      expect(base.isComplete, isFalse);
      expect(
        base
            .copyWith(
              successCount: 0,
              failureCount: 0,
              totalEpisodes: 0,
            )
            .isComplete,
        isFalse,
      );
    });

    test('isDownloadingは進捗があり未完了のときtrueを返す', () {
      expect(base.isDownloading, isTrue);
      expect(
        base.copyWith(successCount: 0, failureCount: 3).isDownloading,
        isTrue,
      );
      expect(
        base.copyWith(successCount: 10, failureCount: 0).isDownloading,
        isFalse,
      );
      expect(
        base.copyWith(successCount: 0, failureCount: 0).isDownloading,
        isFalse,
      );
    });

    test('downloadStatusが未取得・取得中・完了・失敗を返す', () {
      expect(base.copyWith(successCount: 0, failureCount: 0).downloadStatus, 0);
      expect(base.downloadStatus, 1);
      expect(
        base.copyWith(successCount: 10, failureCount: 0).downloadStatus,
        2,
      );
      expect(
        base.copyWith(successCount: 8, failureCount: 2).downloadStatus,
        3,
      );
    });

    test('downloadedEpisodesは成功数を返す', () {
      expect(base.downloadedEpisodes, 5);
    });

    test('sourceを含む全フィールドが等価性に使われる', () {
      expect(base, equals(base.copyWith()));
      expect(base.hashCode, equals(base.copyWith().hashCode));
      expect(base, isNot(equals(base.copyWith(source: NovelSource.narou))));
      expect(base, isNot(equals(base.copyWith(workId: '987654321'))));
      expect(base, isNot(equals(base.copyWith(successCount: 6))));
    });

    test('toStringにsourceとworkIdを含む', () {
      expect(
        base.toString(),
        'NovelDownloadSummary(source: NovelSource.alphapolis, '
        'workId: 123456789, successCount: 5, failureCount: 1, '
        'totalEpisodes: 10)',
      );
    });
  });
}
