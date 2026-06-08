# Configuration Reference

## book.yml Field List

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| [`title`](#index:book.yml/title) | String | Yes | -- | Book title |
| [`description`](#index:book.yml/description) | String | No | (auto) | Description for the OGP / `meta description` tags. Auto-extracted from the cover (or first) chapter's opening prose when omitted |
| [`site_url`](#index:book.yml/site_url) | String | No | -- | Canonical published URL. When set, emits `og:url` and `canonical`. `setup-github-review` seeds it from `repository` (the GitHub Pages URL) |
| [`author`](#index:book.yml/author) | String | No | `""` | Author name |
| [`language`](#index:book.yml/language) | String | No | `"en"` | HTML `lang` attribute |
| [`output_dir`](#index:book.yml/output_dir) | String | No | `"build"` | Output directory |
| [`chapter_numbers`](#index:book.yml/chapter_numbers) | Boolean | No | `true` | Show chapter numbers |
| [`chapters`](#index:book.yml/chapters) | Array | Yes | -- | Chapter, part, and appendix structure |

## chapters Elements

The `chapters` array can contain the following 3 types of elements:

### Chapter (string)

```yaml
chapters:
  - 01-introduction.md
  - 02-getting-started.md
```

### Part

```yaml
chapters:
  - part: part1.md
    chapters:
      - 01-introduction.md
      - 02-getting-started.md
```

Specify a Markdown file for `part`. Its `h1` becomes the part title, and the body becomes the title page.

### Appendix

```yaml
chapters:
  - appendix:
    - a1-references.md
    - a2-glossary.md
```

Appendix chapters are numbered with letters (A, B, C, ...) instead of numbers.
