# マルチサイト拡張 作業結果報告

- 作成日: 2026-08-26
- 対象ブランチ: `feat/multisite-foundation`（`develop` から分岐）
- 規模: 42コミット / 248ファイル / +18,717行 / -1,414行

## 概要

対応サイトを2つ（なろう・カクヨム）から6つへ拡張した。あわせて、拡張の前提として
既存実装の重大な不具合を修正し、サイト追加のたびに手作業が増える箇所を整理した。

## 1. 調査したAPI仕様

### 取得手段の選定

単純なHTMLスクレイピングを第一候補とせず、公式API・内部API・埋め込みJSON・HTMLの
順で検討した。結果は次のとおり。

| サイト | 採用した取得手段 | 備考 |
|---|---|---|
| アルファポリス | 埋め込みJSON + CSRF付きPOST | 本文は `POST /novel/episode_body`。`token` と `X-CSRF-TOKEN` が必要 |
| ハーメルン | 公開HTML | 本文は `#honbun` に直接埋め込み。CSRF不要 |
| エブリスタ | SSR埋め込みJSON + 内部GraphQL | `script#__NUXT_DATA__` と `POST /api/graphql` |
| ノベルアップ＋ | 公開HTML + JSON-LD | `/api/` は robots.txt で禁止のため不使用 |

### 作品IDの形式

アルファポリスのみ `{authorId}/{workId}` の複合IDだった。`workId` に区切り文字を
埋め込んだ単一文字列として保持することで、DBスキーマ・ルータ・`NovelSite`
インターフェースをいずれも変更せずに対応した。他3サイトは数値の単一IDである。

### 公式アプリの静的解析

`docs/novelty/app_api_analysis.md` に詳細を記載。同期APIの仕様を得るために
4アプリを逆コンパイルした。

| アプリ | 結果 |
|---|---|
| カクヨム | ブックマークの一覧・追加・削除、履歴の一括更新と既読化まで仕様候補が判明 |
| アルファポリス | お気に入りの登録と削除を確認。読書位置と認証搬送は未確定 |
| エブリスタ | **WebViewとCookieでログインしている**ことが判明。同期処理はWebView側で未特定 |
| なろう | 公式アプリがFlutter製でAOTコンパイル済みのため、この手法では届かない |

エブリスタの成果が大きい。OAuthのコード交換を自前実装する必要がないと分かり、
カクヨムと同じWebView方式でログインを実装できた。

## 2. 実装したProvider一覧

### サイト実装

| サイト | ランキング | 検索 | ログイン | 同期 |
|---|---|---|---|---|
| なろう | 5種別 | 対応 | フォームPOST | 対応 |
| カクヨム | 5種別 | 対応 | WebView + Cookie | 対応 |
| アルファポリス | 12種別 | 対応 | フォームPOST | 未対応 |
| ハーメルン | 18種別 | 未対応 | フォームPOST | 未対応 |
| エブリスタ | 5種別 | 対応 | WebView + Cookie | 未対応 |
| ノベルアップ＋ | 21種別 | 対応 | フォームPOST | 未対応 |

未対応としたものは、いずれも**仕様が確認できていないため意図的に
`UnsupportedError` にしている**。推測での実装は行っていない。

- ハーメルンの検索: クエリパラメータは判明したが結果のDOMが未確認
- 同期4メソッド: エンドポイントが未確認。フォームPOST方式の3サイトは
  共通基底 `FormAccountSyncAdapter` に集約している

### 共通基盤

- `FormPostAuthService` / `FormAccountSyncAdapter` / `FormAccountLoginPage` —
  フォームPOST方式3サイトの共通化
- `AccountAuthState` / `accountAuthStateProvider(source)` — 認証状態のサイト横断表現
- `AccountTile` — アカウント連携UIの共通化。`NovelSource.values` とレジストリから
  自動で並ぶ
- `RequestRateLimiter` / `siteRateLimiterProvider` — サイトごとに単一のレートリミッタ
- `createNoveltyDio()` — タイムアウト・User-Agent・指数バックオフを集約
- `userAgentPresets` — Android / iOS / Windows / macOS のプリセット

## 3. DB変更

`currentSchemaVersion` を 22 から 23 へ。

v23 のマイグレーションは、目次メタデータが空文字で潰れていた既存データを
NULL へ正規化する。空文字は有効なURLや日時ではなく欠損の表現であるため。

**サイト追加そのものによるスキーマ変更は発生していない。** 既存の
`(source, work_id)` 複合主キーで4サイトとも収まっている。

## 4. 追加ファイル一覧

### パッケージ

- `packages/alphapolis_parser`
- `packages/hameln_parser`
- `packages/estar_parser`
- `packages/novelup_parser`

`estar_parser` のみHTMLではなくプレーンテキストを扱う。GraphQLレスポンスの本文が
`|漢字《よみ》` 記法を含むテキストのため。同じ二重山括弧を使う `《《強調》》` を
ルビと取り違えないことが実装上の要点で、専用のテストで固定している。

### サイト実装

- `lib/sites/{alphapolis,hameln,estar,novelup}/` 各 `_site.dart` と
  `_account_sync_adapter.dart`
- `lib/utils/{alphapolis,hameln,estar,novelup}_uri.dart`
- `lib/screens/{alphapolis,hameln,novelup,estar}_login_page.dart`
- `lib/services/{alphapolis,hameln,novelup,estar}_auth_service.dart`

### 共通基盤

- `lib/services/http_client.dart` / `lib/utils/request_rate_limiter.dart`
- `lib/utils/user_agents.dart` / `lib/utils/auth_failure_message.dart`
- `lib/models/account_auth_state.dart` / `lib/widgets/accounts/account_tile.dart`
- `lib/services/form_post_auth_service.dart` / `lib/sites/form_account_sync_adapter.dart`

### ドキュメント

- `docs/{alphapolis,hameln,estar,novelup}_html/` 各8ファイル
- `docs/novelty/{alphapolis,hameln,estar,novelup}_terms_review.md`
- `docs/novelty/existing_bugs_triage.md` / `account_sync_feasibility.md` /
  `app_api_analysis.md`

## 5. テスト結果

- **794件すべて成功**
- `flutter analyze`: 40件（warning 0 / info 40）。作業開始時の44件から4件減少
- `flutter build macos --debug` 成功、起動確認済み

作業開始時点で `test/screens/more_page_test.dart` の2件が失敗していたが、
認証状態の共通化に伴い解消した。

## 6. 修正した既存の不具合

サイト追加の前提として、既存実装の問題を調査して修正した。
詳細は `docs/novelty/existing_bugs_triage.md`。

### 特に影響が大きかったもの

- **シークレットモード中もリモートへ読書位置を送信していた**。ローカル側にはガードが
  あるのに、直後のリモート送信には無かった
- **Dioのタイムアウトが未設定**だった。無応答時に読書画面が永久にローディングし続ける
- **`customStatement` がDriftのストリームを更新しない**ため、履歴を同期しても
  アプリを再起動するまで画面に反映されなかった
- **レート制限が並行呼び出しに無防備**で、複数の経路がリミッタを通っていなかった。
  フォロー500件の同期で500〜1500リクエストが連続していた
- **パース失敗が「ダウンロード成功」として記録**され、以降キャッシュヒットして
  再取得されなくなっていた
- **ログイン失敗時に進捗表示が回り続ける**。例外処理が3層とも抜けていた

### 拡張時に発見して修正したもの

- **本文パースが `else` で無条件にカクヨムのパーサへ流れる**構造だった。
  3サイト目を追加した時点で本文が静かに壊れる。`NovelSite` の抽象メソッドにした
- **タブを切り替えるたびにランキングを取り直していた**。`RankingNotifier` が
  autoDispose のため、タブを往復するだけでリクエストが飛び続けていた。
  10分キャッシュと300msデバウンスを入れた
- **CIのビルドごとに署名が変わっていた**。デバッグ鍵をリポジトリで共有して固定した

## 7. 今後対応可能なサイト候補

`docs/architecture/adding_a_provider.md` の手順で追加できる。今回の4サイトは
いずれも「enum1行 + サイト実装1つ + レジストリ1行 + パーサーパッケージ1つ」で収まった。

判断の目安は次のとおり。

- **本文がHTMLに直接埋め込まれているか**。ハーメルンとノベルアップ＋は容易だった。
  アルファポリスはCSRF付きPOSTが必要で手間がかかった
- **作品IDが単一要素か**。複合IDは区切り文字の選定が必要になる
- **ルビの記法**。標準の `<ruby>` なら既存パーサーが流用しやすい
- **robots.txt の制約**。ノベルアップ＋は `/api/` が禁止されており内部APIを使えなかった

## 8. 残っている課題

### 同期機能

アルファポリス・ハーメルン・エブリスタ・ノベルアップ＋の4サイトが未対応。
エンドポイントが未確認のため。

カクヨムについては公式アプリの解析で4メソッドの仕様候補が揃っているが、
**認証セッションの搬送方式が未確定**である。静的解析では埋まらないため、
実際の通信を観測する必要がある。これが確定すれば、現在HTMLスクレイピングで
実装している同期を公式APIへ置き換えられ、フォロー500件で8〜25分かかる問題を
根本的に解消できる見込みがある。

### 実機でのログイン検証

6サイトのログインはいずれも**実機で未検証**である。特にフォームPOST方式の3サイトは、
セッションCookieの名前と成功・失敗の判定方法が未確認のまま安全側に倒した実装に
なっている。実際にログインして調整する必要がある。

macOS では `keychain-access-groups` の entitlement が無いため Secure Storage への
書き込みが失敗する。Xcode に Apple ID を登録して開発署名を有効にすれば解決する。
Android は Keystore が entitlement を要求しないためそのまま検証できる。

### ハーメルンのアクセス制限

調査時のアクセス過多により、現在 Cloudflare から HTTP 403 を受けている。
時間を置けば解除される見込み。レート間隔を5秒へ広げ、ランキングのキャッシュも
入れたため再発しにくくなっている。

### その他

- ハーメルンの検索（結果DOMが未確認）
- エブリスタのジャンル絞り込みと評価指標（指定方法と表示上の意味が未確定）
- `pullLibrary` のN+1構造。レート制限を通したことで安全にはなったが、
  フォロー500件で8分20秒から25分かかる。バッチ化の検討が必要
