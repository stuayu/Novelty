import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:novelty/screens/data_storage_page.dart';
import 'package:novelty/services/backup_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data_storage_page_test.mocks.dart';

@GenerateMocks([BackupService])
void main() {
  group('DataStoragePage', () {
    late MockBackupService mockBackupService;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      mockBackupService = MockBackupService();
    });

    testWidgets('ページタイトルが正しく表示される', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: DataStoragePage(backupService: mockBackupService),
          ),
        ),
      );

      expect(find.text('データとストレージ'), findsOneWidget);
    });

    testWidgets('データベースバックアップセクションが表示される', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: DataStoragePage(backupService: mockBackupService),
          ),
        ),
      );

      expect(find.text('データベースのバックアップ'), findsOneWidget);
      expect(find.text('データベースをエクスポート'), findsOneWidget);
      expect(find.text('データベースをインポート'), findsOneWidget);
    });

    testWidgets('データベースエクスポートボタンをタップできる', (WidgetTester tester) async {
      when(mockBackupService.exportDatabaseToFile()).thenAnswer(
        (_) async => '/test/path/novelty_backup.db',
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: DataStoragePage(backupService: mockBackupService),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final exportButton = find.text('データベースをエクスポート');
      expect(exportButton, findsOneWidget);

      await tester.tap(exportButton);
      await tester.pumpAndSettle();

      // バックアップサービスが呼び出されることを確認
      verify(mockBackupService.exportDatabaseToFile()).called(1);
    });

    testWidgets('データベースインポート確認ダイアログが表示される', (WidgetTester tester) async {
      when(mockBackupService.importDatabaseFromFile()).thenAnswer(
        (_) async => const ImportResult(success: true),
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: DataStoragePage(backupService: mockBackupService),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final importButton = find.text('データベースをインポート');
      expect(importButton, findsOneWidget);

      await tester.tap(importButton);
      await tester.pumpAndSettle();

      // 確認ダイアログが表示されることを確認
      expect(find.text('データベースを復元しますか?'), findsOneWidget);
      expect(find.text('キャンセル'), findsOneWidget);
      expect(find.text('復元する'), findsOneWidget);
    });

    testWidgets('ライブラリ自動更新間隔の設定がデフォルト値(3時間ごと)で表示される', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: DataStoragePage(backupService: mockBackupService),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('ライブラリの自動更新間隔'), findsOneWidget);
      expect(find.text('3時間ごと'), findsOneWidget);
    });

    testWidgets('ライブラリ自動更新間隔を変更できる', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: DataStoragePage(backupService: mockBackupService),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.text('3時間ごと'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('1時間ごと').last);
      await tester.pumpAndSettle();

      expect(find.text('1時間ごと'), findsOneWidget);

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getInt('library_metadata_refresh_interval_minutes'),
        equals(60),
      );
    });
  });
}
