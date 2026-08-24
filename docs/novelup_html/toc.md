# 目次

## URLと項目

目次は作品ページ内。各話URLはhttps://novelup.plus/story/{storyId}/{episodeId}。実測例は/story/258567814/492921017。episodeIdも数字の単一要素で、作品IDと組み合わせれば話を一意に識別できる。Noveltyでは目次順をEpisode.index、URLをEpisode.urlに保持する。

各項目は.episodeListItem内の次のDOM。

- .episodeTitle[href]: 話URL
- .episodeTitleのdata-number: 001、002
- .episodeTitle本文: サブタイトル。例「プロローグ」
- .publishDate: 26/8/25 7:07
- .episodeDate内の文字数: 562文字
- .readTime: 1分
- .goodCount: いいね数
- .commentLink: 感想数

章は.episodeListItem.chapterのクラスを実測。ただし章タイトルの専用要素・抽出規則は未確認。

## ページング

372話作品/story/819720642では30件単位でページングされ、?p=1〜?p=4を確認。p=2にはrel="prev"、p=3、最後のページリンクがある。100話超でも全件取得は4リクエスト程度の実例で現実的。

2話作品は1-2件でページングなし。
