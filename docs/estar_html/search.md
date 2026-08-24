# 検索

確認URL: `https://estar.jp/novels?keyword=%E6%81%8B%E6%84%9B`

`keyword`が検索語。実HTMLはタイトル「【恋愛】おすすめの小説を無料で読む｜作品一覧」を返し、SSRの`ModelNovel`に作品ID群を含む。作品リンク形式は`/novels/{workId}`。タグリンクは`/novels?keyword=%23{タグ}`。

検索結果はSSR埋め込みJSON中心で、HTMLに作品本文は埋め込まれない。ページングの一般条件、1ページ件数、追加クエリ名は今回の公開レスポンスでは未確定。検索条件画面の完全なGET仕様も未確認。

実装時は`NovelSearchQuery.word`を`keyword`へ対応させ、検索結果の`workId`を文字列として保持する。ページング仕様を確定するまで全件取得を実装しない。
