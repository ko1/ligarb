# 設定リファレンス

## book.yml フィールド一覧

| フィールド | 型 | 必須 | デフォルト | 説明 |
|-----------|-----|------|-----------|------|
| [`title`](#index:book.yml/title) | String | はい | — | 本のタイトル |
| [`author`](#index:book.yml/author) | String | いいえ | `""` | 著者名 |
| [`language`](#index:book.yml/language) | String | いいえ | `"en"` | HTML の `lang` 属性 |
| [`output_dir`](#index:book.yml/output_dir) | String | いいえ | `"build"` | 出力ディレクトリ |
| [`chapter_numbers`](#index:book.yml/chapter_numbers) | Boolean | いいえ | `true` | 章番号の表示 |
| [`chapters`](#index:book.yml/chapters) | Array | はい | — | 章・パート・付録の構成 |

## chapters の構成要素

`chapters` 配列には、以下の 3 種類の要素を含めることができます:

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
