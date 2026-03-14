# book.yml の書き方

## 基本構造

[`book.yml`](#index:book.yml) は [YAML](#index) 形式の設定ファイルです。以下が基本的な構造です:

```yaml
title: "本のタイトル"
author: "著者名"
language: "ja"
output_dir: "build"
chapters:
  - 01-introduction.md
  - 02-details.md
```

## フィールド一覧

| フィールド | 必須 | デフォルト | 説明 |
|-----------|------|-----------|------|
| [title](#index:book.yml/title) | はい | — | 本のタイトル。ヘッダーと `<title>` に表示 |
| [author](#index:book.yml/author) | いいえ | （空） | 著者名。ヘッダーに表示 |
| [language](#index:book.yml/language) | いいえ | "en" | HTML の lang 属性 |
| [output_dir](#index:book.yml/output_dir) | いいえ | "build" | 出力ディレクトリ（book.yml からの相対パス） |
| [chapter_numbers](#index:book.yml/chapter_numbers) | いいえ | true | 章番号を表示するか |
| [style](#index:book.yml/style) | いいえ | — | カスタム CSS ファイルのパス |
| [repository](#index:book.yml/repository) | いいえ | — | GitHub リポジトリ URL（編集リンク用） |
| [chapters](#index:book.yml/chapters) | はい | — | 章・パート・付録の構成（下記参照） |

## chapters の指定

`chapters` には章のファイルパスをそのまま並べることも、パートや付録で構造化することもできます。

### 表紙（カバーページ）

本の冒頭に[表紙](#index:cover)ページを追加できます。表紙は目次には表示されず、センタリングされたタイトルページとして表示されます:

```yaml
chapters:
  - cover: cover.md
  - 01-introduction.md
```

### シンプルな構成

章をフラットに並べるだけの最もシンプルな形式です:

```yaml
chapters:
  - 01-introduction.md
  - 02-getting-started.md
  - 03-advanced.md
```

### パート（部）で分ける

章が多い本では、[パート](#index:パート)でグループ化できます:

```yaml
chapters:
  - part: part1.md
    chapters:
      - 01-introduction.md
      - 02-getting-started.md
  - part: part2.md
    chapters:
      - 03-advanced.md
      - 04-tips.md
```

`part` には Markdown ファイルを指定します。
そのファイルの h1 がパートのタイトルになり、本文が扉ページとして表示されます。

### 付録を追加する

巻末に[付録](#index:付録)を追加できます。付録の章にはアルファベット（A, B, C, ...）で番号が付きます:

```yaml
chapters:
  - part: part1.md
    chapters:
      - 01-introduction.md
  - appendix:
    - a1-references.md
    - a2-glossary.md
```

### ファイル名の規約

ファイル名に決まりはありませんが、`番号-スラッグ.md` の形式にすると管理しやすくなります。
ファイル名の `番号-スラッグ` 部分がそのまま章の識別子（[slug](#index:slug)）として URL の `#` に使われます。

## カスタム CSS

`style` フィールドで [CSS](#index:カスタム CSS) ファイルを指定すると、デフォルトスタイルの後に読み込まれます:

```yaml
style: "custom.css"
```

CSS カスタムプロパティを上書きすることで、色やフォントなどを変更できます:

```css
:root {
  --color-accent: #e63946;
  --sidebar-width: 320px;
}
```

## GitHub 編集リンク

`repository` フィールドを指定すると、各章の末尾に「View on GitHub」リンクが表示されます（[GitHub 編集リンク](#index:GitHub 編集リンク)）:

```yaml
repository: "https://github.com/user/my-book"
```
