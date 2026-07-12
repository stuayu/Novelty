import 'package:freezed_annotation/freezed_annotation.dart';

/// JSONからint?を変換するコンバーター。
class StringToIntConverter implements JsonConverter<int?, Object?> {
  /// コンストラクタ。
  const StringToIntConverter();

  @override
  int? fromJson(Object? json) {
    if (json is int) {
      return json;
    }
    if (json is double) {
      return json.toInt();
    }
    if (json is String) {
      final numeric = int.tryParse(json);
      if (numeric != null) return numeric;

      // `novelupdated_at` / `updated_at` は日時文字列で返るため、
      // 比較・保存可能な14桁整数へ変換する。
      final digits = json.replaceAll(RegExp(r'\D'), '');
      if (digits.length >= 14) {
        return int.tryParse(digits.substring(0, 14));
      }
    }
    return null;
  }

  @override
  Object? toJson(int? object) {
    return object;
  }
}
