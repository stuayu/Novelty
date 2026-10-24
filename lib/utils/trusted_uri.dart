/// HTTPSの既定ポートで、指定したホストに一致するURIだけを許可する。
bool isTrustedHttpsOrigin(Uri uri, {required String host}) {
  return uri.scheme.toLowerCase() == 'https' &&
      uri.host.toLowerCase() == host.toLowerCase() &&
      uri.port == 443 &&
      uri.userInfo.isEmpty;
}
