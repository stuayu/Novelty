import 'dart:convert';

/// HTTP本文Traceに保存する最大文字数。
const int maxHttpTraceBodyCharacters = 512 * 1024;

/// サイズ制限を適用したHTTP本文Traceデータ。
class CappedHttpTraceBody {
  /// 上限適用後の本文と切り詰め状態を作成する。
  const CappedHttpTraceBody({required this.value, required this.truncated});

  /// Traceへ保存するデータ。
  final Object? value;

  /// 本文を上限で切り詰めたか。
  final bool truncated;
}

/// HTTP本文をJSONで記録できる形にし、最大文字数を適用する。
CappedHttpTraceBody capHttpTraceBody(Object? value) {
  if (value is String) {
    if (value.length <= maxHttpTraceBodyCharacters) {
      return CappedHttpTraceBody(value: value, truncated: false);
    }
    return CappedHttpTraceBody(
      value: value.substring(0, maxHttpTraceBodyCharacters),
      truncated: true,
    );
  }

  final safeValue = _jsonSafe(value);
  final serialized = jsonEncode(safeValue);
  if (serialized.length <= maxHttpTraceBodyCharacters) {
    return CappedHttpTraceBody(value: safeValue, truncated: false);
  }
  return CappedHttpTraceBody(
    value: <String, Object?>{
      'truncated': true,
      'originalCharacters': serialized.length,
      'preview': serialized.substring(0, maxHttpTraceBodyCharacters),
    },
    truncated: true,
  );
}

Object? _jsonSafe(Object? value) {
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  if (value is DateTime) return value.toIso8601String();
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        entry.key.toString(): _jsonSafe(entry.value),
    };
  }
  if (value is Iterable) return value.map(_jsonSafe).toList();
  return value.toString();
}
