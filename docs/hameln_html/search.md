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
