# 検索

トップページの検索フォームは次の実HTMLを確認した。

```html
<form action="https://syosetu.org/search/" method="GET">
  <input type="text" name="word">
  <input type="submit" value="検索">
  <input type="hidden" name="mode" value="search">
</form>
```

基本URLは `https://syosetu.org/search/?mode=search&word={URLエンコード語}`。トップページから確認した短編検索URLは `https://syosetu.org/search/?rensai2=1&rensai3=1&rensai4=1&mode=search`。タグ・原作名・ジャンル相当の検索は `word` に `原作：...`、`舞台：...`、`ジャンル：...` 等を入れる形式が確認できる。

実際の検索結果URLをcurlで取得したところCloudflareのJavaScriptチャレンジとなったため、結果DOM、クエリの全種類、ページングURL、1ページ件数は未確認。検索実装の確定不可。

## 追加確認済み（2026-08-25）

フォームは`GET https://syosetu.org/search/`。主要パラメータは`mode=search`、`word`、`search_type`（`0`小説、`1`各話本文、`2`小説・各話本文）、`gensaku`、`type`、`page`。詳細条件は`mozi1/mozi2`、`mozi1_all/mozi2_all`、`rate1/rate2`、`soupt1/soupt2`、`f1/f2`、`re1/re2`、`v1/v2`、`r1/r2`、`t1/t2`、`d1/d2`。状態は`rensai1..4`、除外タグは`tag2..15`、対象除外は`op1..3/op5`、hiddenは`filter`/`uid`。

`type`の表示値は、最終更新日時、総合評価、通算UA、平均評価、加重平均、1話文字数、初回投稿日、お気に入り、しおり、ここすき、今週/先週UA、投票者数、総評価数、総文字数、感想数、話数、中央値、評価10投票数、日間/週間/月間/四半期/年間総合評価、WSI、相対評価、ピックアップ、ランダム。値はHTML上で`0..44`のうち定義済み値として確認した。

検索結果はランキングと同じ`div.section3[id^="nid_"]`構造。1ページ20件、ページングは`page=2`と`rel="next"`、最終リンクの例は`page=2559`。ジャンル相当の絞り込みは固定IDでなく、`gensaku`または`word`へ`原作：...`、`舞台：...`、`ジャンル：...`を指定する。
