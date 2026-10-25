import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 診断ログ保存先を解決する関数。
typedef AuthDiagnosticsDirectoryResolver = Future<Directory> Function();

/// 診断ログをコンソールへ出力する関数。
typedef AuthDiagnosticsConsoleSink = void Function(String line);

const _captureSensitiveTraceFromEnvironment = bool.fromEnvironment(
  'NAROU_AUTH_TRACE_SENSITIVE',
);

/// アプリ全体の構造化診断ログを出力する。
///
/// 通常の診断ログでは認証情報や応答本文を伏せる。生の通信データは
/// デバッグビルドでTraceを明示的に有効にした場合だけ別ファイルへ出力する。
class AppDiagnosticsLogger {
  /// 診断ログを初期化する。
  AppDiagnosticsLogger({
    bool? enabled,
    bool captureSensitiveTrace = _captureSensitiveTraceFromEnvironment,
    AuthDiagnosticsDirectoryResolver? directoryResolver,
    AuthDiagnosticsConsoleSink? consoleSink,
    this.maxBytes = 512 * 1024,
    this.maxTraceBytes = 5 * 1024 * 1024,
  }) : assert(maxBytes > 0, 'maxBytesは1以上である必要があります'),
       assert(maxTraceBytes > 0, 'maxTraceBytesは1以上である必要があります'),
       enabled = enabled ?? kDebugMode,
       captureSensitiveTrace = kDebugMode && captureSensitiveTrace,
       _directoryResolver = directoryResolver ?? getApplicationSupportDirectory,
       _consoleSink = consoleSink ?? _debugConsoleSink;

  /// 既存の診断ログファイル名。利用者のログ受け渡しパスとの互換性を保つ。
  static const fileName = 'narou_auth_diagnostics.jsonl';

  /// Traceレベルの完全な通信ログ名。
  static const traceFileName = 'narou_auth_trace.jsonl';

  /// 出力上限。超過時は直前のログを1世代だけ保持する。
  final int maxBytes;

  /// Traceログの出力上限。
  final int maxTraceBytes;

  /// ログ出力が有効かどうか。
  final bool enabled;

  /// 認証情報を含むTraceログが有効かどうか。
  final bool captureSensitiveTrace;

  final AuthDiagnosticsDirectoryResolver _directoryResolver;
  final AuthDiagnosticsConsoleSink _consoleSink;
  Future<void> _writeQueue = Future<void>.value();
  int _operationSequence = 0;

  /// 一連のログを相関させる操作IDを生成する。
  String createOperationId() {
    _operationSequence++;
    final timestamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    final timestampPart = timestamp.toRadixString(36);
    final sequencePart = _operationSequence.toRadixString(36);
    return '$timestampPart-$sequencePart';
  }

  /// イベントをコンソールとJSONLファイルへ記録する。
  void record(
    String operationId,
    String event, [
    Map<String, Object?> fields = const <String, Object?>{},
  ]) {
    if (!enabled) return;

    final entry = <String, Object?>{
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'operationId': operationId,
      'event': event,
      ...fields,
    };
    final line = jsonEncode(entry);
    _consoleSink('[NoveltyDiagnostics] $line');
    _enqueue(line, fileName: fileName, maxBytes: maxBytes);
  }

  /// 秘密を含む詳細Traceをローカルの開発ログへ記録する。
  void recordTrace(
    String operationId,
    String event, [
    Map<String, Object?> fields = const <String, Object?>{},
  ]) {
    if (!enabled || !captureSensitiveTrace) return;

    final entry = <String, Object?>{
      ...fields,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'operationId': operationId,
      'level': 'TRACE',
      'event': event,
    };
    final line = jsonEncode(entry);
    _consoleSink('[NoveltyDiagnostics][TRACE] $line');
    _enqueue(line, fileName: traceFileName, maxBytes: maxTraceBytes);
  }

  /// それまでにキューへ追加された書き込みを完了する。
  Future<void> flush() => _writeQueue;

  /// ログファイルのパスを返す。
  Future<String?> logFilePath() async {
    return _filePath(fileName, enabled: enabled);
  }

  /// 完全なTraceログファイルのパスを返す。
  Future<String?> traceLogFilePath() async => _filePath(
    traceFileName,
    enabled: enabled && captureSensitiveTrace,
  );

  Future<String?> _filePath(String name, {required bool enabled}) async {
    if (!enabled) return null;
    try {
      final directory = await _directoryResolver();
      return p.join(directory.path, name);
    } on Object {
      return null;
    }
  }

  void _enqueue(
    String line, {
    required String fileName,
    required int maxBytes,
  }) {
    _writeQueue = _writeQueue
        .then((_) => _append(line, fileName: fileName, maxBytes: maxBytes))
        .catchError((Object error) {
          _consoleSink(
            '[NoveltyDiagnostics] fileWriteFailed '
            'type=${error.runtimeType}',
          );
        });
  }

  Future<void> _append(
    String line, {
    required String fileName,
    required int maxBytes,
  }) async {
    final directory = await _directoryResolver();
    await directory.create(recursive: true);
    final file = File(p.join(directory.path, fileName));
    final lineBytes = utf8.encode('$line\n').length;
    if (file.existsSync() && file.lengthSync() + lineBytes > maxBytes) {
      final rotatedFile = File('${file.path}.1');
      if (rotatedFile.existsSync()) rotatedFile.deleteSync();
      await file.rename(rotatedFile.path);
    }
    await file.writeAsString('$line\n', mode: FileMode.append, flush: true);
  }

  static void _debugConsoleSink(String line) {
    debugPrint(line, wrapWidth: 1200);
  }
}

/// なろう認証サービスとの互換型名。
typedef NarouAuthDiagnosticsLogger = AppDiagnosticsLogger;

/// アプリ内で共有する診断ロガー。
final appDiagnosticsLogger = AppDiagnosticsLogger();

/// 認証・同期・取得処理で共有する診断ログ。
final appDiagnosticsLoggerProvider = Provider<AppDiagnosticsLogger>(
  (ref) => appDiagnosticsLogger,
);

/// 既存のなろう認証コードと診断ログ参照先との互換エイリアス。
final AppDiagnosticsLogger narouAuthDiagnosticsLogger = appDiagnosticsLogger;

/// 既存のなろう認証コードとの互換プロバイダー。
final Provider<AppDiagnosticsLogger> narouAuthDiagnosticsLoggerProvider =
    appDiagnosticsLoggerProvider;
