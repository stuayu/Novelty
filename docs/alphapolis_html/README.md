# アルファポリスHTML調査

- 調査日: 2026-08-24
- 取得方法: `curl` による素HTTP取得。Headless Browser / WebViewは未使用
- User-Agent: `Novelty research contact`
- robots.txt: `User-agent: *` は `/dreambookclub/` のみ禁止。`/dreambookclub/image/` は許可。小説URLは許可。BingbotのCrawl-delayは3秒。Googlebotのページング禁止は `User-agent: *` には適用されない
- 取得間隔: 各リクエスト間1秒以上
- 注意: 実行環境のCA証明書不備によりcurlのTLS検証が失敗したため、採取時は `-k` を使用。実装では証明書検証を無効化しないこと

## Fixture

fixtureは採取HTMLから、対象DOMとJSONをそのまま抜き出した最小サンプル。完全レスポンスではない。

| fixture | 対象 |
|---|---|
| `short_work.html` | 1話完結作品 `/novel/600144500/873826540` |
| `serial_work.html` | 連載作品 `/novel/480761512/519070183` |
| `toc.html` | 連載作品の目次部分 |
| `episode_page.html` | 本文ページの枠と本文取得後の本文部分 |
| `ranking_page.html` | ジャンル一覧1ページ |
| `search_page.html` | `query=異世界` の検索結果1ページ |

## 結論

- 作品情報と目次は作品ページHTMLの `script#app-cover-data` に埋め込まれたJSONから取得可能。`__NEXT_DATA__` は未確認。JSON-LDはパンくずに存在するが、作品情報の主データではない
- 目次は作品詳細ページ内。連載の全話が1レスポンスの `chapterEpisodes` に含まれた実例を確認。100話超作品でページングが発生するかは未確認
- 本文はエピソードHTMLの `#novelBody` が空で、ページ内JavaScriptが `/novel/episode_body` へPOSTして取得する。実POSTで本文HTMLを取得済み
- 規約第10.3項が配信コンテンツの複製を方法を問わず禁止。Noveltyのローカル保存・オフライン読書は適合と判定できない。不適合フラグ。実装着手前に方針決定が必要
