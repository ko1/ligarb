# ligarb

Markdown ファイルから単一ページの HTML 本を生成する CLI ツール。

## プロジェクト構成

- `lib/ligarb/` - メインのソースコード
  - `cli.rb` - コマンドディスパッチ、`--help` / `help` の出力
  - `builder.rb` - ビルドパイプライン（構造読み込み → アセット → テンプレート → 出力）
  - `chapter.rb` - Markdown パース、見出し抽出、mermaid/math ブロック変換、脚注IDスコープ
  - `config.rb` - book.yml の読み込みとバリデーション（part/cover/appendix 構造対応）
  - `template.rb` - ERB テンプレートのレンダリング
  - `asset_manager.rb` - 外部 JS/CSS の自動検出・ダウンロード
  - `initializer.rb` - `ligarb init` の雛形生成
- `templates/book.html.erb` - 出力 HTML のテンプレート（JS 含む）
- `assets/style.css` - 出力 HTML のスタイル（ダークモード含む）
- `test/` - minitest テスト
- `manual/` - マニュアル本（ligarb 自身で作成）
- `docs/help.md` - `ligarb help` の出力内容（Markdown 形式の仕様書）
- `docs/todo.md` - 未実装機能の TODO

## 開発コマンド

```bash
# テスト実行
rake test

# manual/ のビルド
rake manual

# 直接ビルド
ruby exe/ligarb build manual/book.yml

# help 出力確認（AI 向け仕様書を兼ねる）
ruby exe/ligarb help
```

## 重要な設計判断

- 出力は `build/` ディレクトリに `index.html` + `js/` + `css/` + `images/`
- 外部 JS（highlight.js, mermaid, KaTeX）はコードブロックの使用を自動検出し、初回ビルド時にダウンロード。`build/js/`, `build/css/` に配置（既にあればスキップ）
- mermaid/math ブロックは Ruby 側で `<div>` に変換してから出力（HTML エンティティの問題を回避）
- heading ID は Ruby 側で付与（`{slug}--{heading-text}`）。JS での再生成はしない
- 脚注 ID は章の slug でスコープし、単一 HTML 内での衝突を回避
- `ligarb help` は AI が読むことを想定した仕様書を兼ねている
- chapters 配列は 4 種類の要素を持つ: cover, 章（文字列）, part, appendix
- GitHub リンクは `/blob/HEAD/` を使い、ブランチ名の指定を不要にしている
- Git リポジトリルートを自動検出し、章ファイルのパスを解決
- 多言語対応: ハブ `book.yml` が `translations` で言語別設定を参照。共通設定を継承し、サイドバーに言語切り替え UI を表示

## ドキュメント更新時の注意

仕様変更時は以下の 2 箇所を同期すること:
1. `docs/help.md`（`ligarb help` の出力、英語）
2. `manual/chapters/` の該当マニュアル章
