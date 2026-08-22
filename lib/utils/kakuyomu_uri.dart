/// カクヨムの認証済みWebセッションとして信頼できるURLか判定する。
///
/// OAuth中は外部サイトへ遷移するため、それらのページではログイン完了判定や
/// Cookie取り込みを行わない。HTTPSの公式メインホストだけを許可する。
bool isTrustedKakuyomuUri(Uri uri) {
  return uri.scheme.toLowerCase() == 'https' &&
      uri.host.toLowerCase() == 'kakuyomu.jp';
}
