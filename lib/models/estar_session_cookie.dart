/// エブリスタのログインセッションで使用する Cookie。
class EstarSessionCookie {
  /// コンストラクタ。
  const EstarSessionCookie({
    required this.name,
    required this.value,
    required this.domain,
    required this.path,
    this.expiresDate,
    this.isSecure,
    this.isHttpOnly,
  });

  /// JSON保存用Mapから復元する。
  factory EstarSessionCookie.fromJson(Map<String, Object?> json) {
    return EstarSessionCookie(
      name: json['name']! as String,
      value: json['value']! as String,
      domain: json['domain']! as String,
      path: json['path']! as String,
      expiresDate: json['expiresDate'] as int?,
      isSecure: json['isSecure'] as bool?,
      isHttpOnly: json['isHttpOnly'] as bool?,
    );
  }

  /// Cookie名。
  final String name;

  /// Cookie値。
  final String value;

  /// Cookieのドメイン。
  final String domain;

  /// Cookieのパス。
  final String path;

  /// 有効期限（Unix time milliseconds）。
  final int? expiresDate;

  /// Secure属性。
  final bool? isSecure;

  /// HttpOnly属性。
  final bool? isHttpOnly;

  /// エブリスタへ送信してよいCookieかどうか。
  bool get belongsToEstar {
    final normalized = domain.toLowerCase().replaceFirst(RegExp(r'^\.'), '');
    return normalized == 'estar.jp' || normalized.endsWith('.estar.jp');
  }

  /// 現在時刻時点で有効期限切れかどうか。
  bool get isExpired {
    final expires = expiresDate;
    if (expires == null) return false;
    return expires <= DateTime.now().millisecondsSinceEpoch;
  }

  /// JSON保存用Mapへ変換する。
  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'value': value,
    'domain': domain,
    'path': path,
    'expiresDate': expiresDate,
    'isSecure': isSecure,
    'isHttpOnly': isHttpOnly,
  };
}
