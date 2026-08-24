# 目次

## URL

連載目次は作品ページ自身 `https://syosetu.org/novel/{workId}/`。各話は相対URL `./{episodeNumber}.html`、実際の絶対URLは `https://syosetu.org/novel/328453/1.html`。

## DOM

```html
<section class="episode-list" aria-label="話一覧">
  <ul class="episode-list__items">
    <li class="episode-list__chapter">
      <div class="episode-list__chapter-title">番外編</div>
    </li>
    <li class="episode-list__item">
      <a href="./1.html" class="episode-list__link">
        <span class="episode-list__title">エイプリルフール</span>
        <time class="episode-list__date">2025/04/01 23:55</time>
        <span class="episode-list__revision" title="2025/04/02 07:09改稿">(<u>改</u>)</span>
      </a>
    </li>
  </ul>
</section>
```

セレクタは `.episode-list__item > .episode-list__link`、タイトル `.episode-list__title`、日時 `.episode-list__date`、改稿日時 `.episode-list__revision[title]`、章 `.episode-list__chapter-title`。

対象作品では章が8個、話リンクが68個。章は目次HTML内の見出し要素で表現される。

100話超作品について、ページングの有無と全件取得URLは未確認。目次HTML内のページャーは対象作品で確認できず、1ページに全68話が出ていた。100話超作品の実測が必要で、現時点で「1リクエストで全件」または「ページ分割」と断定しない。

話を一意に特定するには、同一作品内で連番となるURL末尾の `{episodeNumber}.html` を使える。アプリ内の `episodeIndex` は目次順、サイトURLは `Episode.url` に保持する方針と整合する。

## 追加確認済み：100話超

作品ID `408150`（「偽典・蓮ノ空女学院スクールアイドルクラブ106期小話」）は、`episode-list__item`が134個、話リンクが133個で、`./1.html`から`./133.html`まで単一HTMLに収まっていた。ページャーおよび`page=`は存在しなかった。目次は作品ページ1回で全話取得し、リンクを順に収集できる。
