# 本文ページ

## URLとHTML埋め込み

連載話は `https://syosetu.org/novel/328453/1.html`。短編は作品URL `https://syosetu.org/novel/424174/` のGETで第1話本文が返った。本文はJavaScript追加取得ではなく、HTMLに直接埋め込まれていた。本文取得にCSRFトークンまたはCookieは不要と判断できる範囲で取得できたが、CloudflareがCookieを発行するため、運用時のCookie要否は再確認が必要。

## セレクタ

|項目|セレクタ|実値・事実|
|---|---|---|
|本文|`#honbun`|本文コンテナ。子要素は`<p id="0">`等|
|段落|`#honbun > p`|`id`は0始まりの連番。空行は全角空白のみの`<p>`として存在|
|話タイトル|`#maind` 内、`span[style*="font-size:120%"]`|短編は`第1話`。専用classなし|
|前書き|`#maegaki`|本文前書き。表示切替用の`#maegaki_open`も存在|
|次話|`#nextpage.novelnavi`|対象短編では空。連載本文は未確認|
|画像|本文HTML内の`#honbun`配下|対象サンプルでは未確認|

## 表現

ルビ、傍点、改ページ、区切り線の実例は取得サンプルでは未確認。`<br>` は本文外の前書き等で確認したが、`#honbun` 内の改行表現としての実例は未確認。改稿日時は目次の `span.episode-list__revision[title]` で確認でき、本文ページ内の表示は未確認。

本文は `<p>` のテキストを段落単位で読み、各`p`の後に `NovelContentElement.newLine()` を追加する。空白だけの`p`は空行として`newLine`にする。`<br>`、ruby、画像、傍点などは実HTMLの追加サンプルを取得してから実装方針を確定する。

## Hybridマッピング

確認済みの本文文字列は `PlainText`、段落境界と空白段落は `NewLine`。ルビを含む実HTMLが未確認のため、`RubyText`への具体的マッピングは未確定。実装時は`NovelContentElement`の`plainText`/`rubyText`/`newLine`を使用し、保存は`HybridConverter.toHybridJson`に任せる。HTMLを独自JSONとして保存しない。

縦書きページへのリンク `/\?mode=ss_detail3&nid=...` は存在するが、本文のルビ表現が同一かは未確認。`packages/tategaki`で扱えるかはルビHTML取得後に検証する。

## 年齢確認

一般作品の取得ではワンクッションページを確認しなかった。R18作品・R18検索へのアクセスは行っていない。R18判別方法、HTTPステータス、年齢確認画面のレスポンスは未確認。
