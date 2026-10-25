const _cookieMonths = <String, int>{
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'apr': 4,
  'may': 5,
  'jun': 6,
  'jul': 7,
  'aug': 8,
  'sep': 9,
  'oct': 10,
  'nov': 11,
  'dec': 12,
};

/// Set-CookieヘッダーをCookie名で既存の値へ統合する。
void mergeSetCookieHeaders(
  Map<String, String> cookies,
  List<String>? headers, {
  Set<String>? allowedNames,
}) {
  if (headers == null) return;
  for (final header in headers) {
    final pair = header.split(';').first.trim();
    final separator = pair.indexOf('=');
    if (separator <= 0) continue;
    final name = pair.substring(0, separator).trim();
    final value = pair.substring(separator + 1).trim();
    if (name.isEmpty ||
        (allowedNames != null && !allowedNames.contains(name))) {
      continue;
    }
    if (isExpiredCookie(header, value)) {
      cookies.remove(name);
    } else {
      cookies[name] = value;
    }
  }
}

/// Set-CookieのMax-AgeまたはExpiresで削除指定されているかを返す。
bool isExpiredCookie(String header, String value) {
  if (value.isEmpty) return true;
  for (final attribute in header.split(';').skip(1)) {
    final trimmedAttribute = attribute.trim();
    final normalized = trimmedAttribute.toLowerCase();
    if (normalized.startsWith('max-age=')) {
      final maxAge = int.tryParse(normalized.substring('max-age='.length));
      if (maxAge != null && maxAge <= 0) return true;
    }
    if (normalized.startsWith('expires=')) {
      final expiresAt = _parseCookieExpiration(
        trimmedAttribute.substring('expires='.length).trim(),
      );
      if (expiresAt != null && !expiresAt.isAfter(DateTime.now().toUtc())) {
        return true;
      }
    }
  }
  return false;
}

DateTime? _parseCookieExpiration(String value) {
  final match = RegExp(
    r'^(?:[a-z]{3},\s*)?(\d{1,2})[\s-]+([a-z]{3})[\s-]'
    r'(\d{4})\s+(\d{2}):(\d{2}):(\d{2})\s+gmt$',
    caseSensitive: false,
  ).firstMatch(value);
  if (match == null) return null;
  final month = _cookieMonths[match.group(2)!.toLowerCase()];
  if (month == null) return null;
  return DateTime.utc(
    int.parse(match.group(3)!),
    month,
    int.parse(match.group(1)!),
    int.parse(match.group(4)!),
    int.parse(match.group(5)!),
    int.parse(match.group(6)!),
  );
}
