# 作品情報

## URLとID

作品ページは https://novelup.plus/story/{storyId}。実測値は /story/258567814、/story/819720642。storyIdは数字だけで構成される単一要素。複合IDではないため区切り文字は不要。

著者ページは https://novelup.plus/user/{userId}/profile。作品URLから作品IDと著者IDを別々に取得する。

## 実測フィールド

| Novelty項目 | DOM / 実測値 |
|---|---|
| title | .storyTitle。例「筆を染める」 |
| writer | .storyAuthorと著者URL |
| story | .novel_synopsis内のp、またはmeta description |
| genre | .story_genre。例「現代/青春ドラマ」 |
| cover | .novel_cover img[src]。例/uploads/150660268/1787581133.jpg |
| 総話数 | .totalEpisode / .total_episode_num |
| 種別 | .story_short。実測で「短編」「長編」「短編集」 |
| 文字数 | カードの.story_length。例「99,849字」 |
| 更新日時 | .story_update。例「2026年8月25日更新」 |
| 初回投稿日時 | JSON-LD datePublished。例2026-08-25 |
| 完結状態 | JSON-LD creativeWorkStatus。実測連載は「連載中」。完結値は未確認 |
| 評価指標 | .story_point、.count_good、.story_point_pay |
| tags | .story_tag a |

作品ページのJSON-LDにはCreativeWork、name、author.name、author.url、url、image、description、genre、creativeWorkStatus、datePublishedを確認。__NEXT_DATA__、Apollo state、作品用の別JSON scriptは未確認。

## 短編と連載

/story/258567814は2話、/story/819720642は372話。検索結果では1話作品が「短編」、複数話作品が「長編」または「短編集」と表示される。短編専用作品ページの直接取得は未確認。取得方法が別になるとは確認できない。

## 日付形式

目次の投稿日時は26/8/25 7:07。カード更新日は2026年8月25日更新。JSON-LD初回投稿日はISO日付。時刻・タイムゾーンを含む初回投稿日時と最終更新日時は未確認。
