# 設定リファレンス

## book.yml フィールド一覧

| フィールド | 型 | 必須 | デフォルト | 説明 |
|-----------|-----|------|-----------|------|
| [`title`](#index:book.yml/title) | String | はい | — | 本のタイトル |
| [`description`](#index:book.yml/description) | String | いいえ | （自動） | OGP・`meta description` 用の説明文。省略時は表紙（または先頭章）の本文冒頭から自動抽出 |
| [`site_url`](#index:book.yml/site_url) | String | いいえ | — | 公開先の正規 URL。設定すると `og:url` と `canonical` を出力。`setup-github-review` が `repository` から GitHub Pages URL を推測して追記 |
| [`author`](#index:book.yml/author) | String | いいえ | `""` | 著者名 |
| [`language`](#index:book.yml/language) | String | いいえ | `"en"` | HTML の `lang` 属性 |
| [`output_dir`](#index:book.yml/output_dir) | String | いいえ | `"build"` | 出力ディレクトリ |
| [`chapter_numbers`](#index:book.yml/chapter_numbers) | Boolean | いいえ | `true` | 章番号の表示 |
| [`chapters`](#index:book.yml/chapters) | Array | はい | — | 章・パート・付録の構成 |

## chapters の構成要素

`chapters` 配列には、以下の 4 種類の要素を含めることができます:

### 表紙（cover）

```yaml
chapters:
  - cover: cover.md
```

`cover` には Markdown ファイルを指定します。本を開いたときに最初に表示されるランディングページになり、サイドバーの目次には表示されません。

### 章（文字列）

```yaml
chapters:
  - 01-introduction.md
  - 02-getting-started.md
```

### パート（part）

```yaml
chapters:
  - part: part1.md
    chapters:
      - 01-introduction.md
      - 02-getting-started.md
```

`part` には Markdown ファイルを指定します。そのファイルの `h1` がパートタイトル、本文が扉ページになります。

### 付録（appendix）

```yaml
chapters:
  - appendix:
    - a1-references.md
    - a2-glossary.md
```

付録の章には数字ではなくアルファベット（A, B, C, ...）で番号が付きます。
