/// カクヨムのログインセッションで使用する Cookie。
///
/// WebView の Cookie 型をそのまま永続化せず、アプリ内で必要な属性だけを
/// 保持する。これにより認証処理を WebView 実装から分離する。
class KakuyomuSessionCookie {
  /// コンストラクタ。
  const KakuyomuSessionCookie({
    required this.name,
    required this.value,
    required this.domain,
    required this.path,
    this.expiresDate,
    this.isSecure,
    this.isHttpOnly,
  });

  /// Cookie 名。
  final String name;

  /// Cookie 値。
  final String value;

  /// Cookie のドメイン。
  final String domain;

  /// Cookie のパス。
  final String path;

  /// 有効期限（Unix time milliseconds）。
  final int? expiresDate;

  /// Secure 属性。
  final bool? isSecure;

  /// HttpOnly 属性。
  final bool? isHttpOnly;

  /// カクヨム本体へ送信してよい Cookie かどうか。
  bool get belongsToKakuyomu {
    final normalized = domain.toLowerCase().replaceFirst(RegExp(r'^\.'), '');
    return normalized == 'kakuyomu.jp' ||
        normalized.endsWith('.kakuyomu.jp');
  }

  /// 現在時刻時点で有効期限切れかどうか。
  bool get isExpired {
    final expires = expiresDate;
    if (expires == null) return false;
    return expires <= DateTime.now().millisecondsSinceEpoch;
  }

  /// JSON 保存用 Map へ変換する。
  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'value': value,
    'domain': domain,
    'path': path,
    'expiresDate': expiresDate,
    'isSecure': isSecure,
    'isHttpOnly': isHttpOnly,
  };

  /// JSON 保存用 Map から復元する。
  factory KakuyomuSessionCookie.fromJson(Map<String, Object?> json) {
    return KakuyomuSessionCookie(
      name: json['name']! as String,
      value: json['value']! as String,
      domain: json['domain']! as String,
      path: json['path']! as String,
      expiresDate: json['expiresDate'] as int?,
      isSecure: json['isSecure'] as bool?,
      isHttpOnly: json['isHttpOnly'] as bool?,
    );
  }
}
