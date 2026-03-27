# 多言語対応（Translations）

ligarb では、1 つの書籍プロジェクトから複数言語の HTML を生成できます。ハブとなる設定ファイルに[多言語対応](#index)の定義を記述し、言語ごとの子設定ファイルで個別の内容を管理します。

## ハブ設定ファイル

プロジェクトのルートに置く `book.yml` が[ハブ](#index:ハブ設定ファイル)の役割を果たします。ここに [`translations`](#index) フィールドを記述し、言語コードと子設定ファイルのパスを対応付けます。

```yaml
repository: "https://github.com/user/repo"
ai_generated: true
bibliography: references.bib
output_dir: "build"
translations:
  ja: book.ja.yml
  en: book.en.yml
```

`translations` の各キーは IETF 言語タグ（`ja`, `en` など）で、値は子設定ファイルへの相対パスです。

## 子設定ファイルと継承

各言語の子設定ファイル（`book.ja.yml`, `book.en.yml` など）は、[`inherit`](#index) フィールドでハブの共通設定を継承します。

日本語版（`book.ja.yml`）:

```yaml
inherit: book.yml
title: "マニュアル"
language: "ja"
output_dir: "build/ja"
chapters:
  - chapters/intro.md
```

英語版（`book.en.yml`）:

```yaml
inherit: book.yml
title: "Manual"
language: "en"
output_dir: "build/en"
chapters:
  - chapters/en/intro.md
```

### 継承のルール

ハブに書いた共通設定（`repository`, `bibliography`, `ai_generated` 等）は子に自動で[継承](#index:設定の継承)されます。子側で同じキーを指定すれば上書きできます。

ただし、`output_dir` は継承されません。`ligarb build` に渡した設定ファイル自身の `output_dir` が常に使われます。

### 言語ごとの必須フィールド

子設定ファイルでは以下のフィールドが必須です:

- `title` -- 書籍タイトル（言語ごとに異なる）
- `language` -- 言語コード
- `chapters` -- 章ファイルのリスト

## ビルド方法

`ligarb build` に渡すファイルによって、統合ビルドと単体ビルドを使い分けられます。

```bash
ligarb build book.yml       # ハブ → 全言語を1ファイルに統合
ligarb build book.ja.yml    # 日本語版のみ
ligarb build book.en.yml    # 英語版のみ
```

たとえば以下の設定の場合:

```yaml
# book.yml       → output_dir: "build"
# book.ja.yml    → output_dir: "build/ja"
# book.en.yml    → output_dir: "build/en"
```

3 つすべてをビルドすると、次のように出力されます:

```
build/
├── index.html        # 統合版（言語切り替え付き）
├── ja/index.html     # 日本語のみ
└── en/index.html     # 英語のみ
```

統合ビルドでは、すべての言語のコンテンツが 1 つの `index.html` に含まれ、JavaScript による[言語切り替え](#index)で表示を切り替えます。単体ビルドでは `inherit` 経由でハブの共通設定を引き継ぎつつ、指定した言語だけの HTML が生成されます。

## 言語切り替え UI

統合ビルドの出力では、サイドバーに言語切り替えボタンが表示されます。たとえば日本語と英語の 2 言語構成なら、`EN | JA` のようなボタンが並びます。

選択した言語は `localStorage` に保存され、次回アクセス時に自動で復元されます。

言語を切り替えると、同じ章の同じセクション位置に移動します。

## ディレクトリ構成例

典型的な多言語プロジェクトのディレクトリ構成は次のようになります:

```
my-book/
├── book.yml          # ハブ（共通設定 + translations）
├── book.ja.yml       # 日本語版
├── book.en.yml       # 英語版
├── chapters/
│   ├── intro.md          # 日本語の章
│   └── en/
│       └── intro.md      # 英語の章
└── images/
```

画像などのアセットは言語間で共有できます。言語固有の画像が必要な場合は、`images/ja/`, `images/en/` のようにサブディレクトリで分けることもできます。
