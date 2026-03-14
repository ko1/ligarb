# インストールと準備

## 必要な環境

ligarb を使うには以下が必要です:

- Ruby 3.0 以上
- Bundler（gem install bundler）

## インストール

ligarb のリポジトリをクローンし、依存ライブラリをインストールします:

```bash
git clone https://github.com/ligarb/ligarb.git
cd ligarb
bundle install
```

## プロジェクトの作成

本のプロジェクトを作成します。以下のディレクトリ構造を用意してください:

```
my-book/
├── book.yml
├── chapters/
│   ├── 01-first-chapter.md
│   └── 02-second-chapter.md
└── images/          # 画像がある場合
    └── screenshot.png
```

`book.yml` が設定ファイル、`chapters/` 以下に各章の Markdown ファイルを配置します。
