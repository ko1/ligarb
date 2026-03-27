# ligarb

<p align="center">
  <img src="manual/images/logo.svg" alt="ligarb" width="400">
</p>

複数の Markdown ファイルから単一ページの HTML 本を生成する CLI ツール。

**[マニュアル（実際の出力例）](https://ko1.github.io/ligarb/manual/build/index.html)**

## 特徴

- Markdown ファイル群 → 単一 `index.html`（Web サーバー不要）
- 検索可能な目次サイドバー（h1〜h3）
- 章ごとの表示切り替え + パーマリンク
- Part / Appendix による構造化
- 章・節の自動ナンバリング
- コードハイライト（highlight.js）、図表（mermaid）、数式（KaTeX）を自動検出・ダウンロード
- 脚注（kramdown 記法、章ごとにスコープ）
- ダークモード切り替え
- カスタム CSS 対応
- GitHub リンク（View on GitHub）
- レスポンシブ・印刷対応（ページ番号付き）
- ローカルサーバー（`ligarb serve`）でライブリロード + レビュー UI

## インストール

```bash
gem install ligarb
```

開発版を使う場合:

```bash
git clone https://github.com/ko1/ligarb.git
cd ligarb
bundle install
```

## クイックスタート

### 1. プロジェクトを作成

```bash
ligarb init my-book
cd my-book
```

`book.yml` と雛形の Markdown ファイルが生成されます。

### 2. book.yml を編集

```yaml
title: "My Book"
author: "Author Name"
language: "ja"
chapters:
  - 01-introduction.md
  - 02-getting-started.md
```

Part や Appendix を使った構造化も可能です:

```yaml
title: "My Book"
author: "Author Name"
language: "ja"
repository: "https://github.com/user/repo"
chapters:
  - cover: cover.md
  - part: part1.md
    chapters:
      - 01-introduction.md
      - 02-getting-started.md
  - part: part2.md
    chapters:
      - 03-advanced.md
  - appendix:
    - a1-references.md
```

### 3. ビルド

```bash
ligarb build
```

`build/index.html` が生成されます。ブラウザで開いてください。

## ローカルサーバーでプレビュー＆レビュー

> **注意:** `ligarb serve` はローカル開発専用です。本番環境やインターネットへの公開には使わないでください。

```bash
ligarb serve              # http://localhost:3000 で配信
ligarb serve --port 8080  # ポート指定
```

- 起動時に自動ビルド
- ソースを変更して `ligarb build` するとブラウザに更新ボタンが表示（Linux では inotify で即検知）
- 本文のテキストを選択すると「Comment」ボタンが出現 → コメントを書くと Claude（Opus）がレビュー
- 提案された変更には「Show patch」で diff を確認、「Approve」で即座にソースに適用＆リビルド
- レビュー履歴は `.ligarb/reviews/` に JSON で保存

[Claude Code](https://claude.com/claude-code) の CLI が必要です。

## AI で本を書く

> **注意:** AI が生成したコンテンツには誤りが含まれる可能性があります。公開前に必ず内容を確認・校正してください。また、AI 生成物の著作権についてはお住まいの地域の法律を確認してください。

`ligarb write` コマンドで、AI（Claude）に本を丸ごと書かせることができます。

```bash
ligarb write --init ruby_book    # ruby_book/brief.yml を生成
vi ruby_book/brief.yml           # 企画を編集
ligarb write ruby_book/brief.yml # 本を生成 + ビルド
```

`brief.yml`（企画書）の例:

```yaml
title: "Ruby入門"
language: ja
audience: "プログラミング初心者"
notes: |
  5章くらいで。
  コード例を多めにしてください。
```

[Claude Code](https://claude.com/claude-code) の CLI が必要です。

### 手動で AI を使う

`ligarb help` の出力は AI が読むことを想定した仕様書を兼ねています。AI に直接読ませることで、仕様に従った本の生成も可能です。

```
$(ligarb help) を読んで、ligarb の仕様に従って「Git 入門」という本を作ってください。
対象読者は初心者で、5 章構成にしてください。
mermaid でワークフロー図を入れてください。
```

## セキュリティモデル

ligarb は、著者自身が作成・確認した Markdown ファイルをローカルでビルドすることを前提としています。信頼できない第三者のコンテンツを処理する用途には設計されていません。

## 詳細仕様

`ligarb help` を実行するか、[docs/help.md](docs/help.md) を参照してください。

## 名前の由来

ラテン語の *ligāre*（束ねる・綴じる）から。

## ライセンス

MIT
