# ノベルアップ＋HTML調査

- 調査日: 2026-08-25
- 対象: https://novelup.plus
- 取得方法: curlによる素HTTP取得。Headless Browser / WebView / Playwright / Seleniumは未使用
- User-Agent: 指定されたChrome互換User-Agent
- 各HTTPリクエスト間隔: 1秒以上
- TLS: 実行環境のCA検証失敗時のみ調査用に-kを使用。実装で証明書検証を無効化しない

## 前回調査の訂正

前回の「CloudFrontのHTTP 403で取得不能」は誤り。研究用User-Agentが弾かれていた。指定User-AgentとHTML向けAcceptヘッダーでは、トップ、作品、本文、検索、ランキング、利用規約をHTTP 200で取得できた。

## robots.txt

全文は [robots.txt](../../test/fixtures/novelup/robots.txt)、取得ヘッダーは robots.headers.txt に保存した。

User-Agent:* の禁止は /my/、/edit/、/api/、/shop/point/。調査ではこれらへアクセスしていない。対象の公開作品、本文、検索、ランキング、/etc/tos、/loginはこの禁止パス外。

## 取得優先順位の結論

1. 公式API: 公開ドキュメント・利用可能なAPIは未確認。
2. 内部API / GraphQL: /api/はrobots.txtで禁止のためアクセスしない。GraphQLも未確認。
3. 埋め込みJSON: 作品・本文ページにJSON-LD（application/ld+json）を確認。
4. HTML DOM: 作品情報、目次、本文、検索、ランキングは公開HTMLから取得できる。

実装候補はJSON-LDを補助に使うHTML DOM解析。/api/を使う実装は候補外。

## 再現コマンドとレスポンス

作品情報・JSON-LD・目次・本文は同じ公開HTML GET。例:

    curl -kfsS \
      -A 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36' \
      -H 'Accept: text/html,application/xhtml+xml' \
      -H 'Accept-Language: ja,en;q=0.9' \
      'https://novelup.plus/story/258567814/492921017'

HTTPメソッドはGET、リクエストパラメータはURL中のstoryIdとepisodeIdのみ。追加ヘッダー、ログインCookie、CSRFは不要。レスポンスContent-Typeはtext/html; charset=UTF-8。JSON-LDはレスポンス内のscript type="application/ld+json"で、独立したJSONエンドポイントではない。

## fixture

| fixture | 対象 |
|---|---|
| short_work.html | 1話作品の公開作品カード断片 |
| serial_work.html | 2話連載作品 /story/258567814 |
| toc.html | 372話作品の目次とページング断片 |
| episode.html | 本文ページ /story/258567814/492921017 |
| ranking_page.html | /ranking/all/day |
| search_page.html | /search?q=異世界 |

## 関連文書

- [作品情報](work.md)
- [目次](toc.md)
- [本文](episode.md)
- [ランキング](ranking.md)
- [検索](search.md)
- [ジャンル](categories.md)
- [懸念事項](concerns.md)
- [利用規約レビュー](../novelty/novelup_terms_review.md)
