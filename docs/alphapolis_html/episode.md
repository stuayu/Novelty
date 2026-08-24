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

---

# 追加調査（2026-08-24 実施）

以下は初回調査の「未確認」項目を実HTMLで確認し直した結果。上記と重複する記述があるが、
こちらが後から実測で確定させた内容である。


対象URL: `https://www.alphapolis.co.jp/novel/{authorId}/{workId}/episode/{episodeNo}`

## 本文POST（確認済み）

- 完全なPOST先: `https://www.alphapolis.co.jp/novel/episode_body`
- bodyは`episode`と`token`の2項目のみ。tokenは同ページのインラインJavaScript、`$('div#novelBody').load()`第2引数に32文字小文字16進で埋め込まれる
- CSRFは同ページの`$.ajaxSetup`内`X-CSRF-TOKEN`値
- 成功時ヘッダー: `X-CSRF-TOKEN`、`Referer`、`X-Requested-With: XMLHttpRequest`、`Content-Type: application/x-www-form-urlencoded; charset=UTF-8`
- GET発行Cookieをcookie jarでPOSTへ送る。非ログインで成功。Cookieなし・CSRF不一致はHTTP 419、`{"message":"CSRF token mismatch."}`
- 成功応答: HTTP 200、`text/html; charset=utf-8`、JSONラップなし

```sh
curl -kfsSL -A 'Novelty research contact' -c cookie.txt -o episode.html \
  'https://www.alphapolis.co.jp/novel/480761512/519070183/episode/11502116'
csrf=$(awk -F'"' '/X-CSRF-TOKEN/{print $2; exit}' episode.html)
token=$(awk -F"'" "/'token'/{print \$6; exit}" episode.html)
sleep 1
curl -kfsS -b cookie.txt -e 'https://www.alphapolis.co.jp/novel/480761512/519070183/episode/11502116' \
  -H 'User-Agent: Novelty research contact' -H 'X-Requested-With: XMLHttpRequest' \
  -H "X-CSRF-TOKEN: $csrf" -H 'Content-Type: application/x-www-form-urlencoded; charset=UTF-8' \
  --data-urlencode 'episode=11502116' --data-urlencode "token=$token" \
  'https://www.alphapolis.co.jp/novel/episode_body'
```

## 本文表現（確認済み）

`<br />`が改行。連続`<br />`は空行。ルビは`<ruby>王族<rt>かぞく</rt></ruby>`、`<ruby>白蛇<rt>エ・ラジャ</rt></ruby>`。傍点、本文画像、改ページ専用要素は採取本文で未確認。`|漢字《よみ》`は検索結果・あらすじでは確認したが本文POSTでは未確認。

## マッピング方針

テキストを`plainText`、`br`を`newLine`へ変換。`ruby`は基底文字を`txt`へ連結し、Hybrid JSONの`rb`（`off`、`base`、`ruby`）へ記録する。`txt.substring(off, off + base.length) == base`を検証。画像・傍点・改ページは専用HTML確認まで潰さない。
