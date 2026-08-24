# ランキング

## URLと種別

入口GET https://novelup.plus/rankingは/ranking/all/dayへ302。ランキングページは公開HTMLで、実測ページにページングリンク all/day?p=2がある。

RankingTypeMaster候補。全て日間URLをランキング一覧で確認した。

| id | label | urlPath |
|---|---|---|
| all | 総合 | /ranking/all/day |
| high-fantasy | 異世界ファンタジー | /ranking/high-fantasy/day |
| low-fantasy | 現代/その他ファンタジー | /ranking/low-fantasy/day |
| sf | SF | /ranking/sf/day |
| romance | 恋愛/ラブコメ | /ranking/romance/day |
| horror | ホラー | /ranking/horror/day |
| mystery | ミステリー | /ranking/mystery/day |
| essay | エッセイ/評論/コラム | /ranking/essay/day |
| history | 歴史/時代 | /ranking/history/day |
| literature | 文芸/純文学 | /ranking/literature/day |
| blog | ブログ/活動報告 | /ranking/blog/day |
| drama | 現代/青春ドラマ | /ranking/drama/day |
| poem | 詩/短歌 | /ranking/poem/day |
| introduction | ノベプラ掲載作品紹介 | /ranking/introduction/day |
| comedy | コメディ/ギャグ | /ranking/comedy/day |
| license | 二次創作 | /ranking/license/day |
| others | 童話/絵本/その他 | /ranking/others/day |
| nuponly | ノベプラオンリー | /ranking/nuponly/day |
| short | 短編小説 | /ranking/short/day |
| shorts | 短編小説集 | /ranking/shorts/day |
| finished | 完結作品 | /ranking/finished/day |

期間はday、week、month、year、millennium。実測ラベルは日間、週間、月間、年間、累計。カードは.story_name、.story_author_name、.story_genre、.story_short、.story_episode_count、.story_length、.story_update、応援ポイント等から構成される。
