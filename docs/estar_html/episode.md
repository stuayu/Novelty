# 本文

## URL・API

本文画面は`https://estar.jp/novels/{workId}/viewer?page={pageNo}`。SSR HTMLにはタイトルと設定があるが、本文`body`が空の状態を確認した。内部APIの`POST https://estar.jp/api/graphql`で本文を取得できる。

|項目|実測|
|---|---|
|Content-Type|`application/json`|
|GraphQL query|`pages/novels/workId/viewer/nextNovelPages`|
|必須data|`workId`, `first`, `pageNoAfter`, `path`|
|fragments|`novelPageInViewer`|
|認証|ログイン不要。GET発行の`guestinfo`/`requestor_id` Cookieが必要|
|CSRF|実測リクエストではCSRFヘッダーなしで成功。ログイン時・別操作での要求は未確認|
|本文形式|JSONの`novel.pages.nodes[].body`にプレーンテキスト|
|状態|`status: published`、`payRequired: false`を実測|

## 本文表現

本文は改行を含むプレーンテキスト。空行は複数の改行で表現される。実本文に`|黛彩葉《まゆずみいろは》`、`|九十九海李《つくもかいり》`を確認した。HTMLの`ruby`/`rt`は本文応答では確認していない。

## NovelContentElementへのマッピング

- 通常文字列を`NovelContentElement.plainText`
- `\n`を`NovelContentElement.newLine`
- `|基底文字《よみ》`を`NovelContentElement.rubyText(基底文字, よみ)`へ変換
- ルビ記法の前後にある文字列を順序維持して分割
- `《《...》》`の強調表現は今回の本文に出現したため、ルビと誤認しない専用判定が必要
- 画像URLを含むMarkdown行（`![alt](url)`）を確認。`NovelContentElement`に画像型がないため、画像を黙って本文文字列へ潰すかは実装方針が必要

`packages/tategaki`の縦書きでルビを扱えるかは、アプリ側変換と表示の結合試験が未実施。コア型はルビを保持できるが、記法ルビからの変換規則は新規実装が必要。
