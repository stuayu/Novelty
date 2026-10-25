import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/services/narou_auth_diagnostics.dart';

void main() {
  late Directory logDirectory;
  late List<String> consoleLines;

  setUp(() async {
    logDirectory = await Directory.systemTemp.createTemp(
      'novelty-narou-auth-diagnostics-test-',
    );
    consoleLines = <String>[];
  });

  tearDown(() async {
    await logDirectory.delete(recursive: true);
  });

  NarouAuthDiagnosticsLogger createLogger({int maxBytes = 512 * 1024}) =>
      NarouAuthDiagnosticsLogger(
        enabled: true,
        directoryResolver: () async => logDirectory,
        consoleSink: consoleLines.add,
        maxBytes: maxBytes,
      );

  test('構造化イベントをコンソールとJSONLファイルへ同じ順序で出力する', () async {
    final logger = createLogger();
    final operationId = logger.createOperationId();

    logger
      ..record(operationId, 'operation.start', <String, Object?>{
        'stage': 'login',
        'rememberSession': true,
      })
      ..record(operationId, 'http.response', <String, Object?>{
        'route': 'login-input',
        'status': 200,
        'durationMs': 42,
      });
    await logger.flush();

    final path = await logger.logFilePath();
    expect(path, isNotNull);
    final lines = await File(path!).readAsLines();
    expect(lines, hasLength(2));
    expect(consoleLines, hasLength(2));
    expect(jsonDecode(lines[0]), containsPair('event', 'operation.start'));
    expect(jsonDecode(lines[0]), containsPair('operationId', operationId));
    expect(jsonDecode(lines[1]), containsPair('route', 'login-input'));
    expect(consoleLines[0], contains(lines[0]));
    expect(consoleLines[1], contains(lines[1]));
  });

  test('サイズ上限を超えたログを1世代だけローテーションする', () async {
    final logger = createLogger(maxBytes: 320);
    final operationId = logger.createOperationId();

    for (var index = 0; index < 8; index++) {
      logger.record(operationId, 'http.response', <String, Object?>{
        'route': 'bookmark-list',
        'status': 200,
        'sequence': index,
      });
    }
    await logger.flush();

    final path = await logger.logFilePath();
    final activeFile = File(path!);
    final rotatedFile = File('$path.1');
    expect(activeFile.existsSync(), isTrue);
    expect(rotatedFile.existsSync(), isTrue);
    expect(activeFile.lengthSync(), lessThanOrEqualTo(320));
    expect(rotatedFile.lengthSync(), lessThanOrEqualTo(320));
  });

  test('無効化時はログを出さずファイルも作らない', () async {
    NarouAuthDiagnosticsLogger(
      enabled: false,
      directoryResolver: () async => logDirectory,
      consoleSink: consoleLines.add,
    ).record('unused', 'operation.start');

    expect(consoleLines, isEmpty);
    expect(await logDirectory.list().toList(), isEmpty);
  });
}
