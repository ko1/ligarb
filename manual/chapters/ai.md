# AI と一緒に使う

## ligarb write — AI で本を自動生成

`ligarb write` コマンドを使うと、[AI](#index:AI 連携)（Claude）に本を丸ごと書かせることができます。
企画書（`brief.yml`）を用意して実行するだけで、Markdown ファイルの生成からビルドまで自動で行います。

### ワークフロー

```bash
ligarb write --init ruby_book    # ruby_book/brief.yml を生成
vi ruby_book/brief.yml           # 企画を編集
ligarb write ruby_book/brief.yml # ruby_book/ に本を生成 + ビルド
ligarb write --no-build          # 生成のみ（ビルドしない）
```

### brief.yml の書き方

最小限はタイトルだけです:

```yaml
title: "Git入門ガイド"
```

詳しく指定することもできます:

```yaml
# brief.yml - 本の企画書
title: "Ruby入門"
language: ja
audience: "プログラミング初心者"
notes: |
  5章くらいで。
  コード例を多めにしてください。
  Railsには触れず、純粋なRubyに絞ってください。
```

| フィールド | 必須 | 説明 |
|-----------|------|------|
| `title` | はい | 本のタイトル |
| `language` | いいえ | 言語（デフォルト: `ja`） |
| `audience` | いいえ | 対象読者 |
| `notes` | いいえ | 追加の指示・要望（自由記述） |
| `sources` | いいえ | AI が参照するファイル一覧（下記参照） |
| `author` | いいえ | 著者名（book.yml に反映） |
| `output_dir` | いいえ | 出力ディレクトリ（book.yml に反映） |
| `chapter_numbers` | いいえ | 章番号の表示（book.yml に反映） |
| `style` | いいえ | カスタム CSS パス（book.yml に反映） |
| `repository` | いいえ | GitHub リポジトリ URL（book.yml に反映） |

`notes` に何でも書けるので、章数の希望、スタイルの指示、含めたい内容、除外したい内容などを自由に記述できます。

### 参照ファイル（sources）

`sources` を指定すると、AI がそのファイルを読んだ上で本を執筆します。既存の資料やメモをもとに本を書かせたいときに便利です:

```yaml
title: "社内システム解説"
sources:
  - architecture.md
  - path: notes/meeting-2025-03.md
    label: "3月会議メモ"
```

文字列で指定するとファイル名がそのままラベルになります。`path` と `label` を個別に指定することもできます。パスは `brief.yml` からの相対パスです。

### AI 生成コンテンツの表示

`ligarb write` で生成した本には、`book.yml` に `ai_generated: true` が自動で設定されます。これにより:

- サイドバーに「AI 生成」バッジが表示される
- 各章の末尾に注意喚起テキストが表示される
- 検索エンジンのインデックスと AI クローラーの学習を抑止するメタタグが追加される

フッターのテキストは `footer` フィールドでカスタマイズできます:

```yaml
ai_generated: true
footer: "AI生成コンテンツです。内容を鵜呑みにしないでください。"
```

`footer` は `ai_generated` とは独立して使うこともできます（著作権表示など）。

### 前提条件

[Claude Code](https://claude.com/claude-code) の CLI（`claude` コマンド）がインストールされている必要があります。

## 手動で AI を使う

`ligarb write` を使わずに、手動で AI に指示することもできます。
`ligarb help` の出力を AI に渡してください:

```bash
ligarb help
```

この出力には設定ファイルの仕様、対応する Markdown 記法、利用可能なコードブロックの種類など、
AI が本を作るために必要な情報がすべて含まれています。

### プロンプト例

#### 新しい本を一から作る

```
ligarb help の出力を読んで、以下の本を作ってください:
- テーマ: Git 入門ガイド
- 対象者: プログラミング初心者
- 章構成: 5 章程度
- 言語: 日本語

ligarb init で雛形を作ってから、章を追加してください。
```

#### 既存のドキュメントを本にする

```
このディレクトリにある Markdown ファイルを ligarb で本にまとめてください。
ligarb help を見て、book.yml を作り、ligarb build でビルドしてください。
```

#### 図や数式を含む本を作る

```
ligarb help を読んで、以下の内容で本を作ってください。
mermaid でアーキテクチャ図を入れてください。

テーマ: Web アプリケーションの設計パターン
```

```
ligarb help を読んで、線形代数の入門書を作ってください。
数式は ```math（KaTeX）を使ってください。
```

#### 章を追加・編集する

```
ligarb help を見て、この本に「デプロイ」の章を追加してください。
book.yml にも登録してください。
```

```
03-api.md の内容を見直して、シーケンス図（mermaid）を追加してください。
```

### 既存の本に翻訳を追加する

すでに日本語で書いた本を海外の読者にも届けたい、あるいは英語の技術ドキュメントに日本語版を追加したい場合があります。ligarb の多言語対応機能（[](translations.md) 参照）を使えば、1 つの HTML に複数言語を収めて言語切り替えで読み分けられます。

AI にこの作業を依頼するときは、既存の `book.yml` をハブに変換し、全章を翻訳するという手順を伝えてください。`ligarb help` に仕様が含まれているため、AI は `translations`、`inherit` などの設定を正しく扱えます。

日本語の本に英語版を追加する例:

```
ligarb help を読んで、この日本語の本に英語版を追加してください。

手順:
1. 既存の book.yml を translations ハブに変換
   - 共通設定（repository, bibliography 等）をハブに残す
   - 日本語固有の設定を book.ja.yml に分離（inherit: book.yml を付ける）
2. chapters/en/ に全章を英語に翻訳
3. book.en.yml を作成（inherit: book.yml）
4. ligarb build book.yml で統合ビルドして確認
```

英語の本に日本語版を追加する場合も同様です:

```
ligarb help を読んで、この英語の本に日本語版を追加してください。

手順:
1. 既存の book.yml を translations ハブに変換
   - 共通設定をハブに残す
   - 英語固有の設定を book.en.yml に分離（inherit: book.yml を付ける）
2. chapters/ja/ に全章を日本語に翻訳
3. book.ja.yml を作成（inherit: book.yml）
4. ligarb build book.yml で統合ビルドして確認
```

#### ビルドと確認

```
ligarb build でビルドしてください。エラーがあれば修正してください。
```

## 注意事項

> [!WARNING]
> AI が生成したコンテンツには誤りが含まれる可能性があります。公開前に必ず内容を確認・校正してください。
> また、AI 生成物の著作権についてはお住まいの地域の法律を確認してください。

## ポイント

- **`ligarb write` を使う**: 企画書を書いて実行するだけで、本の生成からビルドまで自動化できます
- **`ligarb help` を渡す**: 手動で AI を使う場合、仕様を正確に理解させるための最も確実な方法です
- **図を指示する**: 「mermaid で図を入れて」「KaTeX で数式を書いて」と明示すると、AI が適切なコードブロックを使います
- **段階的に進める**: 一度にすべてを指示するより、章ごとに指示した方が品質が上がります
