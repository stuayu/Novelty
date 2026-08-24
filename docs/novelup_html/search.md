# 検索

## URLとパラメータ

GET https://novelup.plus/search?q=異世界。確認したパラメータは次の通り。

- q: 作品名・キーワード
- sort: 1 更新順（エピソード）、2 新着順（作品）、3 ブックマーク数、4 総合ランキング日間、8 総合ランキング累計、9 応援ポイント、10 ノベラポイント
- p: ページ番号
- genre[1]〜genre[14]、genre[52]、genre[99]: ジャンル絞り込み
- search[story]、search[introduction]、search[tag]、search[member]、search[license]: キーワード対象
- short、not-short、finish: 短編・長編・完結絞り込みのリンクを確認
- search[tag]=1: タグ検索のリンクを確認

## 実測結果

q=異世界は「検索結果：8,478件」、1ページ目は1-30件、最後のページはp=283。1ページ30件、ページングは&sort=1&p=2形式。

DOMは.searchResultList > li内の.story_name、.story_author_name、.story_genre、.story_short、.story_episode_count、.story_length、.story_update、.story_introduction、.story_tag。作品ID・著者IDは各リンクから取得できる。
