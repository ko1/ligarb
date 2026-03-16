# ligarb

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

## AI で本を書く

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

## 詳細仕様

[docs/spec.md](docs/spec.md) を参照してください。

## ライセンス

MIT
