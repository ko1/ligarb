# Multi-Language Support (Translations)

ligarb can generate HTML output in multiple languages from a single book project. You define [translations](#index) in a hub configuration file and manage per-language content through child configuration files.

## Hub Configuration File

The `book.yml` at the project root serves as the [hub](#index:hub configuration file). It contains the [`translations`](#index) field, which maps language codes to child configuration files.

```yaml
repository: "https://github.com/user/repo"
ai_generated: true
bibliography: references.bib
output_dir: "build"
translations:
  ja: book.ja.yml
  en: book.en.yml
```

Each key under `translations` is an IETF language tag (`ja`, `en`, etc.), and the value is a relative path to the child configuration file.

## Child Configuration Files and Inheritance

Each language's child configuration file (`book.ja.yml`, `book.en.yml`, etc.) uses the [`inherit`](#index) field to inherit shared settings from the hub.

Japanese version (`book.ja.yml`):

```yaml
inherit: book.yml
title: "マニュアル"
language: "ja"
output_dir: "build/ja"
chapters:
  - chapters/01-intro.md
```

English version (`book.en.yml`):

```yaml
inherit: book.yml
title: "Manual"
language: "en"
output_dir: "build/en"
chapters:
  - chapters/en/01-intro.md
```

### Inheritance Rules

Shared settings written in the hub (`repository`, `bibliography`, `ai_generated`, etc.) are automatically [inherited](#index:configuration inheritance) by child files. A child can override any inherited key by specifying it directly.

However, `output_dir` is not inherited. The `output_dir` of whichever config file is passed to `ligarb build` is always used.

### Required Fields per Language

The following fields are required in each child configuration file:

- `title` -- The book title (different for each language)
- `language` -- The language code
- `chapters` -- The list of chapter files

## Building

You can produce an integrated build or standalone per-language builds depending on which file you pass to `ligarb build`.

```bash
ligarb build book.yml       # Hub: all languages in one file
ligarb build book.ja.yml    # Japanese only
ligarb build book.en.yml    # English only
```

For example, given these settings:

```yaml
# book.yml       → output_dir: "build"
# book.ja.yml    → output_dir: "build/ja"
# book.en.yml    → output_dir: "build/en"
```

Building all three produces:

```
build/
├── index.html        # Integrated (with language switcher)
├── ja/index.html     # Japanese only
└── en/index.html     # English only
```

The integrated build includes content for all languages in a single `index.html`, with a JavaScript-based [language switcher](#index) to toggle the display. Standalone builds inherit shared settings from the hub via `inherit`, but generate HTML for the specified language only.

## Language Switcher UI

In the integrated build output, the sidebar displays language switcher buttons. For example, with a Japanese and English configuration, buttons like `EN | JA` appear.

The selected language is stored in `localStorage` and automatically restored on the next visit.

## Directory Structure Example

A typical [multi-language](#index:multi-language) project directory looks like this:

```
my-book/
├── book.yml          # Hub (shared settings + translations)
├── book.ja.yml       # Japanese version
├── book.en.yml       # English version
├── chapters/
│   ├── 01-intro.md       # Japanese chapters
│   └── en/
│       └── 01-intro.md   # English chapters
└── images/
```

Assets such as images can be shared across languages. If language-specific images are needed, you can organize them into subdirectories like `images/ja/` and `images/en/`.
