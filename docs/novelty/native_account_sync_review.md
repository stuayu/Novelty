# Novelty ネイティブアカウント同期 実装・解析レビュー資料

最終更新: 2026-08-22

## 1. 目的

この文書は、Novelty のカクヨム／小説家になろうアカウント連携について、別の AI や人間が実装根拠を追跡しやすいように整理するためのレビュー資料である。

特に以下を区別する。

- **確認済み仕様**: 現行公式クライアント、現行 Web bundle、実レスポンス等から確認できたもの
- **実装済み**: `develop` に接続済みの機能
- **未完了／未確定**: 推測を避けるため未接続のもの
- **検証状況**: unit test / analyze / format / 実通信確認の状態

## 2. 絶対条件

1. Headless Browser / Headless WebView をアカウント同期には使用しない。
2. フォロー、解除、読書履歴等のサイト状態変更は、確認済み API を Dio 等から直接呼ぶネイティブ HTTP 実装とする。
3. API URL、GraphQL operation、variables、Cookie/CSRF 仕様を推測して実装しない。
4. 認証回避、CAPTCHA 回避、証明書ピニング回避等は行わない。
5. API 同期失敗によって Novelty のローカル読書機能そのものを停止させない。
6. Cookie、トークン等の秘密情報をログ／fixture／レビュー資料へ保存しない。
7. 調査用 workflow / probe は最終成果物整理時に削除し、必要な根拠のみこの文書へ要約する。

> 現在のカクヨムログイン画面は、ユーザー自身が公式ログイン UI を操作する可視 WebView を利用している。ログイン後の作品フォロー等に Headless WebView は使用しない。ログイン自体も完全ネイティブ化する場合は、公式 OAuth フローを別途確認してから置き換える。

## 3. カクヨム

### 3.1 確認済み API 基盤

- GraphQL endpoint: `https://kakuyomu.jp/graphql`
- HTTP method: `POST`
- Web クライアントで確認した基本形式:
  - query parameter: `opname=<operationName>`
  - JSON body: `operationName`, `variables`, `query`
- 認証が必要な操作では、Novelty が保存済みのカクヨムセッション Cookie を HTTP `Cookie` header として利用する。
- 低レベル実装: `lib/services/kakuyomu_graphql_service.dart`

### 3.2 作品フォロー／解除

2026-08-22 に現行 Next.js bundle から以下を確認した。

#### FollowWork

```graphql
mutation FollowWork($input: FollowWorkInput!) {
  followWork(input: $input) {
    work {
      id
      visitorWorkFollowing {
        id
      }
    }
  }
}
```

実 call site の variables:

```text
input.workId = work.id
```

#### UnfollowWorks

```graphql
mutation UnfollowWorks($input: UnfollowWorksInput!) {
  unfollowWorks(input: $input) {
    works {
      id
      visitorWorkFollowing {
        id
      }
    }
  }
}
```

実 call site の variables:

```text
input.workIds = [work.id]
```

実装:

- `lib/services/kakuyomu_follow_service.dart`
- `lib/sites/kakuyomu/kakuyomu_account_sync_adapter.dart`
- `test/services/kakuyomu_follow_service_test.dart`
- `test/sites/kakuyomu/kakuyomu_account_sync_adapter_test.dart`

Headless WebView 実装は撤去済み。

### 3.3 フォロー一覧の取り込み

現在は認証済み HTML の `/my/antenna/works/...` を Dio で取得し、Novelty ライブラリへ取り込む。

実装済み防御:

- Cookie 無しをセッション切れとして扱う
- ログイン URL への redirect を検出
- guest ページを空一覧と誤認しない
- リクエスト間隔を制御
- 既存の詳細メタデータを一覧由来の簡易情報で上書きしない

将来的に公式 GraphQL のフォロー一覧 query が十分に確認できた場合は、HTML 依存を GraphQL へ置換する余地がある。

### 3.4 読書履歴／続きから読む

#### 確認済み

現行 bundle には次の mutation が存在する。

```graphql
mutation RecordReadingHistory($input: RecordReadingHistoryInput!) {
  recordReadingHistory(input: $input) {
    clientMutationId
  }
}
```

`IncrementReadCount` も別 mutation として存在するが、Novelty の目的はアカウントの「続きから読む」同期であり、閲覧数を不必要に増加させる操作は接続しない方針とする。

Novelty の `pushReadingProgress(workId, episode)` の `episode` は 1 始まりのローカル連番であり、カクヨムの remote episode ID ではない。

そのため同期時は必ず:

```text
local episode number
  -> DB に保存済み Episode.url
  -> /works/{workId}/episodes/{episodeId}
  -> numeric episodeId
```

の順で remote ID を解決する。

`lib/utils/kakuyomu_uri.dart` に remote episode ID の安全な抽出処理を実装済み。

#### 未完了

`RecordReadingHistoryInput` の実 call site / server validation の最終確認中。必須 input が確認できるまで adapter への書き込み同期は接続しない。

### 3.5 共通アカウント UI

More 画面からサイト別アカウント UI を専用 Widget へ分離済み。

- `lib/widgets/accounts/kakuyomu_account_tile.dart`
- `lib/widgets/accounts/narou_account_tile.dart`

## 4. 小説家になろう

既存実装はサイトログイン Cookie と Web 側機能を利用した同期が中心。

カクヨム完了後、公式 Android アプリの現行版を対象として以下を静的解析する。

1. API host / protocol
2. 認証方式
3. ブックマーク／しおり／閲覧履歴
4. 更新通知／未読情報
5. 作品詳細・本文取得方式
6. 既存 Novelty 実装より安全・高速・安定に置換可能な API があるか

難読化されている値や通信先を推測で復元しない。公式アプリ解析で確証が取れない場合は「未確認」と明記し、既存実装を無理に置換しない。

## 5. テスト／CI 状況

### 確認できているもの

- Kakuyomu account adapter の主要 unit test は GitHub Actions 上で成功実績あり。
- follow / unfollow は transport 差し替えによる unit test を持つ。
- API probe は実ユーザー Cookie を利用せず、公開 bundle の静的解析と未認証時の入力検証だけを行う。

### 現在の注意点

`mise run check` は現時点でリポジトリ全体の lint warning / info が残っているため失敗する。最終レビュー前に新規変更由来と既存分を切り分け、可能な範囲で zero lint に戻す。

実ユーザーアカウントを用いた follow/unfollow の破壊的 E2E は CI では行わない。

## 6. 最終整理チェックリスト

- [ ] Kakuyomu `RecordReadingHistory` の入力仕様確定
- [ ] Kakuyomu 読書履歴同期実装と unit test
- [ ] Kakuyomu native sync 一式の CI 確認
- [ ] Kakuyomu 調査用 workflow / trigger / raw probe result を整理
- [ ] Kakuyomu 一時 research PR を close
- [ ] Narou 公式アプリ API 静的解析
- [ ] Narou 既存同期との比較と改善実装
- [ ] リポジトリ全体の analyze / format / test 状況を記録
- [ ] 最終 HEAD と変更ファイル一覧を本書へ追記
