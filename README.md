# ligarb

<p align="center">
  <img src="manual/images/logo.svg" alt="ligarb" width="400">
</p>

複数の Markdown ファイルから、単一ページの HTML 本を生成する CLI ツールです。Web サーバー不要の `index.html` が 1 つできあがります。

**[マニュアル（ligarb 自身で作った実際の出力例）](https://ko1.github.io/ligarb/manual/build/index.html)**

## 特徴

- Markdown ファイル群 → 単一 `index.html`（外部依存なしで開ける）
- 検索可能な目次サイドバー（h1〜h3）、章ごとの表示切り替えとパーマリンク
- Part / Appendix による構造化と、章・節の自動ナンバリング
- コードハイライト・図表・数式・関数グラフを**自動検出してダウンロード**
  （highlight.js / mermaid / KaTeX / function-plot）
- 脚注（kramdown 記法、章ごとにスコープ）、ダークモード、カスタム CSS
- レスポンシブ & 印刷対応（ページ番号付き）
- 多言語対応（言語切り替え UI 付き）

## インストール

```bash
gem install ligarb
```

## クイックスタート

```bash
ligarb init my-book   # book.yml と雛形 Markdown を生成
cd my-book
ligarb build          # build/index.html を生成
```

`book.yml` で構成を編集します:

```yaml
title: "My Book"
author: "Author Name"
language: "ja"
repository: "https://github.com/user/repo"   # 任意（View on GitHub リンク用）
chapters:
  - cover: cover.md          # 表紙
  - part: part1.md           # パート
    chapters:
      - 01-introduction.md
      - 02-getting-started.md
  - appendix:                # 付録
    - a1-references.md
```

`chapters` の要素は **cover / 章（文字列）/ part / appendix** の 4 種類です。設定キーの一覧は [`ligarb help`](docs/help.md) を参照してください。

## コマンド

| コマンド | 説明 |
|---|---|
| `ligarb init [DIR]` | 新規プロジェクトの雛形を生成 |
| `ligarb build [book.yml]` | 本をビルド（既定: `book.yml`） |
| `ligarb serve` | ローカルサーバーでプレビュー（後述） |
| `ligarb write [brief.yml]` | AI に本を書かせる（後述） |
| `ligarb setup-github-review` | GitHub 公開・レビューの足場を生成（後述） |
| `ligarb help` | 仕様書を出力（AI に読ませる前提の詳細仕様） |

## ローカルサーバーでプレビュー＆レビュー

> **注意:** `ligarb serve` はローカル開発専用です。インターネットへの公開には使わないでください。

```bash
ligarb serve              # http://localhost:3000 で配信
ligarb serve --port 8080  # ポート指定
```

- 起動時に自動ビルド。ソースを編集して `ligarb build` するとブラウザに更新ボタンが出ます（Linux では inotify で即検知）。
- 本文を選択して「Comment」でコメントすると、Claude（Opus）がレビューし、変更を提案します。「Show patch」で diff を確認、「Approve」でソースに適用＆リビルド。
- レビュー履歴は `.ligarb/reviews/` に JSON で保存されます。

レビュー機能には [Claude Code](https://claude.com/claude-code) の CLI が必要です。

## AI で本を書く

> **注意:** AI 生成物には誤りが含まれることがあります。公開前に必ず内容を確認・校正してください。

```bash
ligarb write --init ruby_book    # ruby_book/brief.yml を生成
vi ruby_book/brief.yml           # 企画を編集
ligarb write ruby_book/brief.yml # 本を生成してビルド
```

`brief.yml`（企画書）の例:

```yaml
title: "Ruby入門"
language: ja
audience: "プログラミング初心者"
notes: |
  5章くらいで。コード例を多めにしてください。
```

[Claude Code](https://claude.com/claude-code) の CLI が必要です。手動で使う場合は `ligarb help` の出力（AI 向け仕様書を兼ねる）を AI に読ませると、仕様に従った本を生成できます。

## GitHub で公開・レビューする

`ligarb setup-github-review` を実行すると、本を GitHub Pages で公開し、読者からフィードバックを受け取るための足場を既存プロジェクトに追加します。

```bash
cd my-book
ligarb setup-github-review   # .github/ + SETUP.md + SETUP.sh + README.md を生成
```

生成されるもの:

- **GitHub Pages 公開** — push でビルド & 公開、PR でビルド検証（いずれも Claude 非依存）
- **読者フィードバック** — 構造化された Issue テンプレートと、本文中の「Report as issue」UI（完全に静的。`book.yml` に `github_review.enabled: true` がある場合に注入）
- **Claude 連携（オプトイン）** — 読者の Issue を Claude が確認して PR やコメントを返す／PR コメントに応答する

生成ファイルは**上書き**されます（`book.yml` と既存 `README.md` は保持）。トークン登録やリポジトリ設定など手作業が必要な手順は、生成される `SETUP.md` を参照してください（`bash SETUP.sh` で一括設定できます）。

## セキュリティモデル

ligarb は、著者自身が作成・確認した Markdown をローカルでビルドすることを前提としています。信頼できない第三者のコンテンツを処理する用途には設計されていません。

## 名前の由来

ラテン語の *ligāre*（束ねる・綴じる）から。

## ライセンス

MIT
