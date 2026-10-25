/// なろうの認証・同期で使用する安全なHTTPS originか判定する。
bool isTrustedNarouUri(Uri uri) =>
    uri.scheme == 'https' &&
    uri.host == 'syosetu.com' &&
    uri.port == 443 &&
    uri.userInfo.isEmpty;

/// なろうのログイン画面またはログイン処理配下のURLか判定する。
bool isNarouLoginUri(Uri uri) =>
    isTrustedNarouUri(uri) &&
    (uri.path == '/login' || uri.path.startsWith('/login/'));
