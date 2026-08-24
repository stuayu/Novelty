# 本文ページ

対象: `https://www.alphapolis.co.jp/novel/{authorId}/{workId}/episode/{episodeNo}`

## HTML

| 項目 | セレクタ /取得先 | 実値・状態 |
|---|---|---|
| 作品タイトル | `.p-novel-episode__title` 内の `a` | 作品名。hrefは作品URL |
| 著者 | `.p-novel-episode__author a` | `さくらろ`。hrefは著者URL |
| 章名 | `.p-novel-episode__chapter-title` | `深夜の清掃員と、ありえない攻略記録` |
| 話タイトル | `.p-novel-episode__episode-title` | `第1話「数字にならない男」` |
| 本文コンテナ | `#novelBody.p-novel-episode__text` | 初期HTMLでは空。POST後に本文HTMLが入る |
| ページ数 | `.p-novel-episode__page-count` | `1 / 62` |
| 本文取得 | POST `/novel/episode_body` | `episode` とページ内生成 `token`、CSRFヘッダーが必要 |

本文POSTの実レスポンスは、テキストと連続する `<br />` のみだった。採取例:

```html
　クラン「ゼノギア」の応接室は、床が鏡みたいに光っていた。<br />
<br />
　昨夜、俺がワックスを二度がけしたからだ。<br />
```

## 未確認・不在だった表現

採取本文で以下は未確認。サイト全体で存在しないとは断定しない。

- `<ruby>` / `<rt>`、`|漢字《かんじ》`形式、独自ルビクラス
- 傍点クラス・記法
- 挿絵・本文画像
- 改ページ・区切り線専用要素
- 改稿日時の本文ページ表示

確認できた空行は連続 `<br />`。空の `<p>` は未確認。

## 前後ナビゲーション

本文HTMLの前後リンクは実レスポンスで未確認。ページ内には `.app-episode-navigation.p-novel-episode__navigation-wrap` とJSON設定があり、クライアント側処理で表示する構造。固定CSSセレクタとしてリンクを断定しない。

## `NovelContentElement` への方針

- `#novelBody` のHTMLを本文パーサーへ渡す
- テキストノードを `plainText`、`<br>` を `newLine` へ変換
- 連続 `<br>` は実際の空行数を保持
- `<ruby>` 等が将来確認できた場合だけ、専用要素またはHybrid JSONのルビ情報へ変換。現採取物にはルビ実装を推測で追加しない
- 画像、傍点、改ページは実HTML確認後に専用マッピングを決める。未確認のまま通常文字列へ潰さない
- `packages/tategaki` との縦書き互換性は、ルビを含む実fixture取得後に別途検証。現時点は未確認
