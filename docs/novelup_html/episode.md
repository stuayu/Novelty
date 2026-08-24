# 本文ページ

## 取得

本文ページはGET https://novelup.plus/story/{storyId}/{episodeId}。HTTP 200のHTMLに本文が直接埋め込まれている。追加の本文API、CSRFトークン、Cookieは不要。本文取得用XHR、/api/呼び出しは未確認。

本文コンテナは<p id="episode_content">。話タイトルは.episode_title h1。前後リンクは.episodeHeaderPagerのa。JSON-LDは@type: Chapterとheadline、url、著者を含む。

## 実測HTML表現

    <p id="episode_content">筆を染める：
    初めて文章や絵を書き始めること、
    または執筆に取りかかること。

    「えっと、<ruby><rb>南埜</rb><rp>(</rp><rt>みなみの</rt><rp>)</rp></ruby>サン」</p>

- 改行: p内の実改行。空行も実改行
- ルビ: ruby rb 親文字 rp 括弧 rt 読み rp 括弧
- 傍点、挿絵・本文画像、改ページ・区切り線: 対象fixtureでは未確認
- 前書き・後書き: 容器は確認、内容は空
- 改稿日時: 本文ページでは未確認

## NovelContentElementへのマッピング

episode_contentのDOMを解析し、テキストノードをplainText、brまたはDOM上の改行をnewLineへ変換する。rubyはrbをbase、rtをrubyとしてrubyText(base, ruby)へ変換する。rpは表示用括弧なので捨てる。標準rubyを確認済みで、既存型で表現可能。縦書き描画は統合テストが必要で未検証。
