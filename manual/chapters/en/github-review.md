# Publish and Review on GitHub

If the [`ligarb serve`](#index:ligarb serve) review UI is for local authoring, this is for
**having readers review your published book**.
[`ligarb setup-github-review`](#index:ligarb setup-github-review) scaffolds a complete workflow
into an existing project: publish the book to GitHub Pages, let readers send feedback as GitHub
Issues, and—optionally—have [Claude](#index:AI integration) respond with Pull Requests.

```bash
ligarb setup-github-review                 # Set up in the current directory
ligarb setup-github-review path/to/book    # Specify a directory
ligarb setup-github-review --owner my-org  # Set the repository owner
```

It works on any project that has a `book.yml`—whether created with
[`ligarb init`](#index:ligarb init), [`ligarb write`](#index:ligarb write), or by hand.

## What Gets Generated

It creates the workflows under `.github/`, plus `SETUP.md` / `SETUP.sh` describing the setup steps.

| File | Role | Needs Claude |
| --- | --- | --- |
| `.github/workflows/deploy-book.yml` | Build the book on push and publish to GitHub Pages | No |
| `.github/workflows/build-check.yml` | Verify `ligarb build` passes on PRs | No |
| `.github/ISSUE_TEMPLATE/book-feedback.yml` | Structured reader feedback form | No |
| `.github/workflows/claude-feedback.yml` | Claude triages issues into PRs/comments | Yes |
| `.github/workflows/claude-pr-mention.yml` | Claude replies to PR comments | Yes |
| `SETUP.sh` | gh CLI script that does repo creation through publishing in one shot | Yes |

It also adds [`github_review`](#index:book.yml/github_review)`.enabled: true` to `book.yml`
(enabling the reader-facing "Report as issue" UI) and generates a `README.md` linking to the
published page (an existing `README.md` is never overwritten). It also derives the GitHub Pages
URL from `repository` and writes [`site_url`](#index:book.yml/site_url) to `book.yml`, so the
build output gets `og:url` and `canonical` (edit it if you use a custom domain).

> [!NOTE]
> Only template copies are generated; ligarb itself never calls Claude or GitHub at runtime.
> For the steps to actually activate the Claude integration and workflows, see the generated
> `SETUP.md` (it includes a gh CLI quickstart).

## repository and --owner

The `__OWNER__` / `__REPO__` placeholders in the workflows and forms are filled from
`book.yml`'s [`repository`](#index:book.yml/repository). When `repository` is unset, this command
writes a default value of `https://github.com/<owner>/<directory-name>` into `book.yml`.

`<owner>` is resolved as follows:

- The value of `--owner` (alias `--user`) when given. Use this **to publish under an organization**.
- Otherwise the `$USER` environment variable.

```bash
# Example: seed the guess as my-org/my-book
ligarb setup-github-review --owner my-org
```

> [!IMPORTANT]
> Passing `--owner` when `repository` is **already set** is an error. The command never rewrites it
> for you, so to change the owner, edit `repository` in `book.yml` directly and then run
> `ligarb setup-github-review` again (the placeholders are regenerated with the new value).

## Re-running

Running the command again after upgrading `ligarb` **overwrites** the scaffolding files with the
latest templates (`book.yml` is left alone). Review the changes with `git diff` and revert any local
edits you want to keep.
