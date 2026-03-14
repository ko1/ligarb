# ligarb

複数の Markdown ファイルから単一の HTML ファイルを生成する CLI ツール。

## 特徴

- Markdown ファイル群 → 単一 `index.html`
- 検索可能な目次サイドバー（h1〜h3）
- 章ごとの表示切り替え + パーマリンク
- レスポンシブ・印刷対応
- Web サーバー不要（ファイルを開くだけ）

## インストール

```bash
git clone https://github.com/ligarb/ligarb.git
cd ligarb
bundle install
```

## クイックスタート

### 1. プロジェクトを作成

```
my-book/
├── book.yml
├── chapters/
│   ├── 01-introduction.md
│   └── 02-details.md
└── images/
    └── screenshot.png
```

### 2. book.yml を書く

```yaml
title: "My Book"
author: "Author"
language: "ja"
chapters:
  - chapters/01-introduction.md
  - chapters/02-details.md
```

### 3. ビルド

```bash
ruby exe/ligarb build my-book/book.yml
```

`build/index.html` が生成されます。ブラウザで開いて確認してください。

## AI 連携

`ligarb help` の出力を AI に読ませることで、AI が仕様に従って本を自動生成できます。

```bash
ruby exe/ligarb help
```

## サンプル

`example/` にチュートリアル本が含まれています:

```bash
ruby exe/ligarb build example/book.yml
open example/build/index.html
```

オンラインでも確認できます: [ligarb チュートリアル](https://ko1.github.io/ligarb/example/build/index.html)

## 詳細仕様

[docs/spec.md](docs/spec.md) を参照してください。

## ライセンス

MIT
