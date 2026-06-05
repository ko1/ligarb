# GitHub で公開・レビュー

[`ligarb serve`](#index:ligarb serve) のレビュー UI がローカルでの執筆支援なら、こちらは
**公開した本を読者からレビューしてもらう**ための仕組みです。
[`ligarb setup-github-review`](#index:ligarb setup-github-review) は、本を GitHub Pages に公開し、
読者が GitHub Issue でフィードバックを送り、必要に応じて [Claude](#index:AI 連携) が
Pull Request を返す——という一連のワークフローを既存プロジェクトに生成します。

```bash
ligarb setup-github-review                 # カレントディレクトリにセットアップ
ligarb setup-github-review path/to/book    # ディレクトリを指定
ligarb setup-github-review --owner my-org  # repository の owner を指定
```

`book.yml` が存在するプロジェクトであれば、[`ligarb init`](#index:ligarb init) や
[`ligarb write`](#index:ligarb write) で作ったものでも、手作りのものでも実行できます。

## 何が生成されるか

`.github/` 以下のワークフローと、セットアップ手順を記した `SETUP.md` / `SETUP.sh` が生成されます。

| ファイル | 役割 | Claude 依存 |
| --- | --- | --- |
| `.github/workflows/deploy-book.yml` | push で本をビルドし GitHub Pages に公開 | なし |
| `.github/workflows/build-check.yml` | PR で `ligarb build` が通るか検証 | なし |
| `.github/ISSUE_TEMPLATE/book-feedback.yml` | 読者向けフィードバックフォーム | なし |
| `.github/workflows/claude-feedback.yml` | Issue を Claude が処理し PR/コメントを返す | あり |
| `.github/workflows/claude-pr-mention.yml` | PR コメントに Claude が応答 | あり |
| `SETUP.sh` | リポジトリ作成〜公開を一括実行する gh CLI スクリプト | あり |

あわせて `book.yml` に [`github_review`](#index:book.yml/github_review)`.enabled: true` を追記し
（読者向けの「Report as issue」UI を有効化）、公開ページへのリンク入り `README.md` を生成します
（既存の `README.md` は上書きしません）。

> [!NOTE]
> 生成されるのはテンプレートのコピーだけです。ligarb 自体は実行時に Claude や GitHub を呼びません。
> Claude 連携やワークフローを実際に動かす手順は、生成された `SETUP.md`（gh CLI のクイックスタート付き）
> を参照してください。

## repository と --owner

各ワークフローやフォームの `__OWNER__` / `__REPO__` プレースホルダは、`book.yml` の
[`repository`](#index:book.yml/repository) から埋められます。`repository` が未設定の場合、
このコマンドはデフォルト値 `https://github.com/<owner>/<ディレクトリ名>` を `book.yml` に書き込みます。

`<owner>` は次のように決まります。

- `--owner`（別名 `--user`）を指定すればその値。**組織（org）に公開したいとき**に使います。
- 指定しなければ環境変数 `$USER`。

```bash
# 例: my-org/my-book として推測値をセット
ligarb setup-github-review --owner my-org
```

> [!IMPORTANT]
> `repository` が**すでに設定済み**の状態で `--owner` を渡すとエラーになります。
> 勝手に書き換えることはしないので、owner を変えたいときは `book.yml` の `repository` を
> 直接編集してから、もう一度 `ligarb setup-github-review` を実行してください
> （プレースホルダが新しい値で再生成されます）。

## 再実行について

`ligarb` を更新したあとに同じコマンドを再実行すると、足場ファイルが最新テンプレートに**上書き更新**されます
（`book.yml` は対象外）。手を入れた箇所は `git diff` で確認し、残したい変更は戻してください。
