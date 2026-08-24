# 目次

目次専用の公開URLは作品ページから確認できず、作品ページ`/novels/{workId}`内のSSR状態・画面リンクで提供される。読書入口は`/novels/{workId}/viewer?page=1`。

実測した連載ID `26544596` は、SSR状態に`episodeCount:34`、各話の`episodeNo`、`title`、`pageNo`、`pageCountInEpisode`を含む。各話URLは作品IDとページ番号を直接含まず、`/novels/{workId}/viewer?page={pageNo}`でページを指定する。GraphQL応答の`novelPageId`がページ一意ID。

|項目|実測|
|---|---|
|章|`chapterTitle`フィールドの存在を確認。ID 26544596では空/未設定の話もある|
|話タイトル|`title`。例: `プロローグ`、`冷たい人`|
|投稿日時|公開ページの話オブジェクトで`publishedAt`フィールドを確認。実値は対象fixtureで未確認|
|文字数|作品ページの総文字数は確認。各話文字数は未確認|
|ページング|本文ページは15ページ単位の内部API応答。目次が100話超でページングする実例は未確認|

## 内部API

追加ページ取得は次の実測リクエスト。`first=15`固定で、`pageNoAfter`を更新して次の15ページを取得する。本文は話単位ではなくページ単位なので、100話超の全件取得リクエスト数は作品の総ページ数に依存し、今回の調査では確定不可。

```sh
curl -kfsSL -A 'Novelty research contact' \
  -b cookie.txt -H 'Content-Type: application/json' -H 'Accept: application/json' \
  -H 'x-from: https://estar.jp/novels/26544596/viewer?page=1' \
  --data '{"query":"pages/novels/workId/viewer/nextNovelPages","data":{"workId":"26544596","first":15,"pageNoAfter":1,"path":"/novels/26544596/viewer"},"fragments":["novelPageInViewer"]}' \
  'https://estar.jp/api/graphql'
```

Cookieは公開ページGETで発行される`guestinfo`と`requestor_id`。ログイン不要、CSRF不要。`novelPageId`は数字文字列。
