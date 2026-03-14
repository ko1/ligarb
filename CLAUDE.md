# ligarb

Markdown ファイルから単一ページの HTML 本を生成する CLI ツール。

## プロジェクト構成

- `lib/ligarb/` - メインのソースコード
  - `cli.rb` - コマンドディスパッチ、`--help` / `help` の出力
  - `builder.rb` - ビルドパイプライン（章の読み込み → アセット → テンプレート → 出力）
  - `chapter.rb` - Markdown パース、見出し抽出、mermaid/math ブロック変換
  - `config.rb` - book.yml の読み込みとバリデーション
  - `template.rb` - ERB テンプレートのレンダリング
  - `asset_manager.rb` - 外部 JS/CSS の自動検出・ダウンロード
  - `initializer.rb` - `ligarb init` の雛形生成
- `templates/book.html.erb` - 出力 HTML のテンプレート（JS 含む）
- `assets/style.css` - 出力 HTML のスタイル
- `example/` - チュートリアル本（ligarb 自身で作成）
- `docs/spec.md` - 日本語の詳細仕様

## 開発コマンド

```bash
# ビルド実行
ruby exe/ligarb build example/book.yml

# 新規プロジェクト作成
ruby exe/ligarb init /tmp/test-book

# help 出力確認（AI 向け仕様書を兼ねる）
ruby exe/ligarb help
```

## 重要な設計判断

- 出力は `build/` ディレクトリに `index.html` + `js/` + `css/` + `images/`
- 外部 JS（highlight.js, mermaid, KaTeX）はコードブロックの使用を自動検出し、初回ビルド時にダウンロード。`build/js/`, `build/css/` に配置（既にあればスキップ）
- mermaid/math ブロックは Ruby 側で `<div>` に変換してから出力（HTML エンティティの問題を回避）
- 本のディレクトリ構成はフラット（`chapters/` サブディレクトリは使わない）
- heading ID は Ruby 側で付与（`{slug}--{heading-text}`）。JS での再生成はしない
- `ligarb help` は AI が読むことを想定した仕様書を兼ねている

## ドキュメント更新時の注意

仕様変更時は以下の 3 箇所を同期すること:
1. `lib/ligarb/cli.rb` の `print_spec`（`ligarb help` の出力、英語）
2. `docs/spec.md`（日本語の詳細仕様）
3. `example/chapters/` の該当チュートリアル章
