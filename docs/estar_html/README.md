# エブリスタHTML/API事前調査

- 調査日: 2026-08-25
- 取得方法: `curl`による素HTTP取得。Headless Browser、WebView、Playwright、Seleniumは未使用
- 対象: 非ログインの公開作品。年齢制限本文は採取していない
- TLS: 調査環境のCAチェーン不備により`curl -k`を使用。製品実装で検証無効化は禁止
- リクエスト間隔: 1秒以上
- robots: `https://estar.jp/robots.txt`はHTTP 404。本文はJSON形式のエラー応答で、禁止規則は返らなかった。404を許可の根拠にせず、最小取得・1秒以上・公開URL限定とする

## Fixture

`test/fixtures/estar/`に、実取得レスポンスから必要部分を抜き出した最小サンプルを置く。

| fixture | 対象 |
|---|---|
| `short_work.html` | 作品ID `594`、短編、`/novels/594` |
| `serial_work.html` | 作品ID `26544596`、連載、`/novels/26544596` |
| `toc.html` | 連載作品のSSR埋め込み状態と目次概要 |
| `episode.html` | GraphQL `nextNovelPages`の実レスポンス抜粋 |
| `ranking.html` | 総合人気・日間ランキング1ページの実レスポンス概要 |
| `search.html` | `keyword=恋愛`検索1ページの実レスポンス概要 |

## 取得手段の結論

公式公開APIのドキュメントは未確認。Webフロントが使用する内部APIとして、`POST /api/graphql`を確認した。作品ページはSSR HTML内の`#__NUXT_DATA__`に作品情報・目次の状態を含む。本文はSSR時に本文が空の場合があるが、GraphQLの`nextNovelPages`で非ログイン取得できた。

優先順位上の結論は「公式APIなし（未確認）、内部GraphQLあり、SSR埋め込みJSONあり、HTMLは補助」。実装候補は内部GraphQL。ただし第10条3項の規約問題で実装着手は未承認状態。
