# ビルドと確認

## ビルドコマンド

本のプロジェクトディレクトリで以下を実行します（[`ligarb build`](#index:ligarb build)）:

```bash
ligarb build
```

`book.yml` が別の場所にある場合は、パスを指定できます:

```bash
ligarb build path/to/book.yml
```

## 出力結果

ビルドが成功すると、`output_dir` に指定したディレクトリ（デフォルトは `build/`）に以下が生成されます:

```
build/
├── index.html    # 全章を含む単一 HTML ファイル
└── images/       # コピーされた画像ファイル
```

## 確認方法

生成された [`index.html`](#index:index.html) をブラウザで直接開くだけで閲覧できます。
Web サーバーは不要です:

```bash
# macOS の場合
open build/index.html

# Linux の場合
xdg-open build/index.html
```

## 動作確認のポイント

ビルド後に以下を確認してください:

- **目次**: 左サイドバーに全章の見出しが表示されているか
- **章の切り替え**: 目次をクリックして章が切り替わるか
- **検索**: 検索窓にキーワードを入力して目次が絞り込まれるか
- **パーマリンク**: URL の `#` に章のスラッグが付き、リロードしても同じ章が表示されるか
- **画像**: Markdown で参照した画像が正しく表示されるか
