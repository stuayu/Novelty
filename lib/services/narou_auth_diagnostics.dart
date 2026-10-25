import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 診断ログ保存先を解決する関数。
typedef AuthDiagnosticsDirectoryResolver = Future<Directory> Function();

/// 診断ログをコンソールへ出力する関数。
typedef AuthDiagnosticsConsoleSink = void Function(String line);

/// なろう認証の構造化診断ログを出力する。
///
/// 記録する値は呼び出し側で選別し、認証情報や応答本文を渡さない。
class NarouAuthDiagnosticsLogger {
  /// 診断ログを初期化する。
  NarouAuthDiagnosticsLogger({
    bool? enabled,
    AuthDiagnosticsDirectoryResolver? directoryResolver,
    AuthDiagnosticsConsoleSink? consoleSink,
    this.maxBytes = 512 * 1024,
  }) : assert(maxBytes > 0, 'maxBytesは1以上である必要があります'),
       enabled = enabled ?? kDebugMode,
       _directoryResolver = directoryResolver ?? getApplicationSupportDirectory,
       _consoleSink = consoleSink ?? _debugConsoleSink;

  /// 診断ログファイル名。
  static const fileName = 'narou_auth_diagnostics.jsonl';

  /// 出力上限。超過時は直前のログを1世代だけ保持する。
  final int maxBytes;

  /// ログ出力が有効かどうか。
  final bool enabled;

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
    _consoleSink('[NarouAuthDiagnostics] $line');
    _writeQueue = _writeQueue.then((_) => _append(line)).catchError((
      Object error,
    ) {
      _consoleSink(
        '[NarouAuthDiagnostics] fileWriteFailed '
        'type=${error.runtimeType}',
      );
    });
  }

  /// それまでにキューへ追加された書き込みを完了する。
  Future<void> flush() => _writeQueue;

  /// ログファイルのパスを返す。
  Future<String?> logFilePath() async {
    if (!enabled) return null;
    try {
      final directory = await _directoryResolver();
      return p.join(directory.path, fileName);
    } on Object {
      return null;
    }
  }

  Future<void> _append(String line) async {
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

/// アプリ内で共有するなろう認証診断ロガー。
final narouAuthDiagnosticsLogger = NarouAuthDiagnosticsLogger();
