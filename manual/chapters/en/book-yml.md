# Writing book.yml

## Basic Structure

[`book.yml`](#index:book.yml) is a [YAML](#index) configuration file. Here is the basic structure:

```yaml
title: "Book Title"
author: "Author Name"
language: "en"
output_dir: "build"
chapters:
  - 01-introduction.md
  - 02-details.md
```

## Field List

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| [title](#index:book.yml/title) | Yes | -- | Book title. Shown in the header and `<title>` |
| [author](#index:book.yml/author) | No | (empty) | Author name. Shown in the header |
| [language](#index:book.yml/language) | No | "en" | HTML `lang` attribute |
| [output_dir](#index:book.yml/output_dir) | No | "build" | Output directory (relative to book.yml) |
| [chapter_numbers](#index:book.yml/chapter_numbers) | No | true | Whether to show chapter numbers |
| [style](#index:book.yml/style) | No | -- | Path to a custom CSS file |
| [repository](#index:book.yml/repository) | No | -- | GitHub repository URL (for edit links) |
| [ai_generated](#index:book.yml/ai_generated) | No | false | Mark as AI-generated content (badge, disclaimer, noindex meta tags) |
| [footer](#index:book.yml/footer) | No | -- | Text displayed at the bottom of each chapter (can override `ai_generated` default disclaimer) |
| [bibliography](#index:book.yml/bibliography) | No | -- | Path to bibliography data file (`.yml` or `.bib`) |
| [sources](#index:book.yml/sources) | No | -- | Reference files for AI writing |
| [translations](#index:book.yml/translations) | No | -- | Multi-language support (lang code to config path) |
| [inherit](#index:book.yml/inherit) | No | -- | Parent config path (inherits shared settings) |
| [chapters](#index:book.yml/chapters) | Yes | -- | Chapter, part, and appendix structure (see below) |

## Specifying Chapters

`chapters` can list chapter file paths directly, or organize them into parts and appendices.

### Cover Page

You can add a [cover](#index:cover) page at the beginning of the book. The cover is not shown in the table of contents and is the first page displayed when the book is opened:

```yaml
chapters:
  - cover: cover.md
  - 01-introduction.md
```

### Simple Structure

The simplest format lists chapters flat:

```yaml
chapters:
  - 01-introduction.md
  - 02-getting-started.md
  - 03-advanced.md
```

### Grouping with Parts

For books with many chapters, you can group them into [parts](#index:parts):

```yaml
chapters:
  - part: part1.md
    chapters:
      - 01-introduction.md
      - 02-getting-started.md
  - part: part2.md
    chapters:
      - 03-advanced.md
      - 04-tips.md
```

Specify a Markdown file for `part`.
Its h1 becomes the part title, and the body becomes the title page.

### Adding Appendices

You can add [appendices](#index:appendices) at the end. Appendix chapters are numbered with letters (A, B, C, ...):

```yaml
chapters:
  - part: part1.md
    chapters:
      - 01-introduction.md
  - appendix:
    - a1-references.md
    - a2-glossary.md
```

### File Naming Conventions

There are no strict rules for file names, but `number-slug.md` is recommended for easy management.
The `number-slug` portion becomes the chapter identifier ([slug](#index:slug)) used in the URL `#`.

## Custom CSS

Specify a [CSS](#index:custom CSS) file with the `style` field. It is loaded after the default styles:

```yaml
style: "custom.css"
```

Override CSS custom properties to change colors, fonts, etc.:

```css
:root {
  --color-accent: #e63946;
  --sidebar-width: 320px;
}
```

## GitHub Edit Links

Set the `repository` field to show "View on GitHub" links at the bottom of each chapter ([GitHub edit links](#index:GitHub edit links)):

```yaml
repository: "https://github.com/user/my-book"
```

## AI-Generated Mark

Setting `ai_generated` to `true` has the following effects:

- Displays an "AI Generated" badge in the sidebar
- Automatically adds a disclaimer footer to each chapter
- Adds `noindex` / `noai` meta tags (suppresses search indexing and AI training)

```yaml
ai_generated: true
```

## Footer

Use the `footer` field to display text at the bottom of each chapter. It can also override the default `ai_generated` disclaimer:

```yaml
footer: "(c) 2025 Author Name. All rights reserved."
```

## Bibliography

Specify a bibliography data file with the `bibliography` field. Both YAML (`.yml`) and BibTeX (`.bib`) formats are supported:

```yaml
bibliography: references.bib
```

See [Markdown Syntax](markdown.md#bibliography) for detailed usage.

## Source Files (sources)

The `sources` field specifies files for the AI to reference during [AI writing](ai.md) (`ligarb write`). The contents are passed as context to the AI:

```yaml
sources:
  - notes.md
  - path: data/research.pdf
    label: "Research Report"
```

A plain string uses the filename as the label. You can also specify `path` and `label` separately.

## Multi-Language Support (translations / inherit)

The `translations` field manages multiple language versions of the same book. The `inherit` field inherits shared settings from a parent config.

```yaml
# book.yml (hub)
repository: "https://github.com/user/repo"
translations:
  ja: book.ja.yml
  en: book.en.yml
```

```yaml
# book.ja.yml (child)
inherit: book.yml
title: "Manual"
language: "ja"
chapters:
  - 01-intro.md
```

See [](translations.md) for details.
