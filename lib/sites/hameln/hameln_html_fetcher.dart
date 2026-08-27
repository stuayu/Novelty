/// ハーメルンHTMLを取得する関数。
typedef HamelnHtmlFetcher = Future<String> Function(String url);

/// WebViewに保存されたハーメルンCookieをHTTP用に読む関数。
typedef HamelnCookieHeaderFetcher = Future<String?> Function(String url);

/// CloudflareのJavaScriptチャレンジページか判定する。
///
/// `challenge-platform` は `/cdn-cgi/challenge-platform/scripts/jsd/main.js`
/// を読み込むスクリプトで、チャレンジを通過した通常ページにも常に含まれる。
/// 判定に使うと正常なHTMLをチャレンジ中と取り違えるため、実測で
/// チャレンジページにのみ現れる文言だけを見る。
bool isHamelnChallengeHtml(String html) {
  final lower = html.toLowerCase();
  return lower.contains('<title>just a moment...</title>') ||
      lower.contains('challenge-error-text');
}
