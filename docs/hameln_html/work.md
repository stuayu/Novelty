# 作品詳細ページ

## URLと作品ID

連載の実例は `https://syosetu.org/novel/328453/`。作品IDはパス中の10進数字 `328453`。短編の実例は `https://syosetu.org/novel/424174/` で、作品URLのGET結果が第1話本文を返した。観測範囲ではIDは単一要素であり、複合IDではない。`workId` は数字文字列をそのまま使える。

著者URLは `https://syosetu.org/user/346407/`。IDは数字。

## 連載目次HTMLの実測セレクタ

対象: 作品ID `328453`、タイトル「道化の愉快な仲間たち」。

|項目|セレクタ|実値・事実|
|---|---|---|
|作品ルート|`#maind[itemscope="https://schema.org/CreativeWork"]`|`#maind` に `itemscope itemtype="https://schema.org/CreativeWork"`|
|タイトル|`#maind span[itemprop="name"]`|道化の愉快な仲間たち|
|著者|`#maind span[itemprop="author"] > a`|UBW・HF、`/user/346407/`|
|原作/ジャンル相当|`span[itemprop="genre"]`|「原作：…」のリンク。サイトの固定ジャンルIDは未確認|
|タグ|`span[itemprop="keywords"] > a`|ダンジョンに出会いを求めるのは間違っているだろうか、ベル・クラネル等|
|あらすじ|タイトル直後の `.ss` ブロック|固定クラス・属性による専用セレクタは未確認。`<br>` を含むテキスト|
|カバー画像|該当作品HTML内の作品情報領域|未確認|

作品本文ページでは短編の作品ヘッダが `.ss` 内の `span[style*="font-size:120%"] > a`、著者が同じ行のテキストとして出る。連載目次と短編本文で作品情報DOMが異なるため、専用パーサーでは両方を分岐する必要がある。

## 状態・日時・評価

目次の実HTMLには作品全体の総文字数、初回投稿日時、最終更新日時、完結状態をまとめた専用フィールドを確認できなかった。トップページの一覧では作品ごとに `連載：<a>68話</a>` または `完結：<a>2話</a>` と表示されるため、一覧では状態を判別できる。

目次の各話日時は `time.episode-list__date`。例: `2023/10/20 02:32`。一部だけ `datetime="2025-04-01T23:55Z"` または `datetime="2026-08-24T23:17Z"` を持つ。改稿日時は `span.episode-list__revision[title]` の `2026/02/26 16:53改稿` 形式。

評価指標は作品本文HTMLの評価リンク（`a[href*="mode=rating_input"]`）までは確認できたが、作品評価値を作品詳細から取得する構造は未確認。`NovelSite.metaText` の値は要追加調査。

## 完結判定

トップページの一覧に実際に `完結：<a ...>2話</a>` があり、連載作品は `連載：...`。ただし作品目次HTML単体での完結フラグは未確認。作品一覧または検索結果の状態表示を採用できるか、実レスポンス取得後に確定する。

## 追加確認済み（2026-08-25）

検索・ランキング一覧で短編を含む作品情報DOMを確認した。状態は`.blo_wasuu_base span[title]`の`連載(連載中)`等、話数は同ブロック内の最新話リンク数字、総文字数は`div[title="総文字数"]`。短編も同ブロックで`短編`と表示される。

|項目|セレクタ・形式|
|---|---|
|作品ID/タイトル|`.blo_title_base > a[href*="/novel/"]`。URLは`/novel/数字/`|
|著者|`.blo_title_sak`内の`a`またはテキスト|
|あらすじ|`.all_arasuji .blo_inword`|
|状態・総話数|`.blo_wasuu_base span[title]`、最新話リンク数字|
|総文字数|`.blo_wasuu_base div[title="総文字数"]`。例`1,212,880 字`|
|最終更新日時|`.blo_date[title="最終更新日"]`の日付と子`div`の時刻|
|評価|`.blo_hyouka .blo_mix`の`調整平均：8.74`、総合値は`.all_keyword`の`評価：数字`|
|お気に入り・感想|`.all_keyword`の`お気に入り：数字`、`a[href*="mode=review"]`|

初回投稿日時は検索フォームの並び替え項目としては存在するが、一覧の専用DOMは今回未確認。目次側も作品全体の初回投稿日時・最終更新日時・総文字数・評価値をまとめた専用フィールドは未確認。`NovelInfo.generalFirstup`は未確定。
