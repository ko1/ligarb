# TODO

## コードタブ

連続するコードブロックをタブ UIでまとめて表示する機能。記法の設計が必要。

他ツールの例:
- mdBook: `{{#tabs}}` テンプレート記法
- Quarto: `::: {.panel-tabset}` の div 記法

## 章間の相互参照

章をまたいだリンクの仕組み。リンク記法と ID 解決の設計が必要。

他ツールの例:
- mdBook: `[text](../chapter/file.md#heading)`（相対パスベース）
- Quarto: `@sec-label`（ラベルベース）
- Sphinx: `:ref:`role`（ロールベース）

ligarb は単一 HTML なので、slug ベースの `#chapter-slug--heading-id` リンクを Markdown 内から簡潔に書ける記法があると良い。
