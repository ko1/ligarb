# Using AI

## ligarb write -- Auto-Generate a Book with AI

The `ligarb write` command lets [AI](#index:AI integration) (Claude) write an entire book.
Prepare a brief (`brief.yml`) and run the command to automate everything from Markdown generation to building.

### Workflow

```bash
ligarb write --init ruby_book    # Generate ruby_book/brief.yml
vi ruby_book/brief.yml           # Edit the brief
ligarb write ruby_book/brief.yml # Generate book in ruby_book/ + build
ligarb write --no-build          # Generate only (skip build)
```

### Writing brief.yml

The minimum is just a title:

```yaml
title: "Git Getting Started Guide"
```

You can specify more details:

```yaml
# brief.yml - Book brief
title: "Ruby for Beginners"
language: en
audience: "Programming beginners"
notes: |
  About 5 chapters.
  Include plenty of code examples.
  Focus on pure Ruby, no Rails.
```

| Field | Required | Description |
|-------|----------|-------------|
| `title` | Yes | Book title |
| `language` | No | Language (default: `ja`) |
| `audience` | No | Target audience |
| `notes` | No | Additional instructions (free text) |
| `sources` | No | Reference files for AI (see below) |
| `author` | No | Author name (passed to book.yml) |
| `output_dir` | No | Output directory (passed to book.yml) |
| `chapter_numbers` | No | Show chapter numbers (passed to book.yml) |
| `style` | No | Custom CSS path (passed to book.yml) |
| `repository` | No | GitHub repository URL (passed to book.yml) |

You can write anything in `notes`, including desired number of chapters, style instructions, content to include or exclude, etc.

### Reference Files (sources)

Specifying `sources` lets the AI read those files before writing the book. This is useful when you want the book based on existing materials or notes:

```yaml
title: "Internal System Documentation"
sources:
  - architecture.md
  - path: notes/meeting-2025-03.md
    label: "March Meeting Notes"
```

A plain string uses the filename as the label. You can also specify `path` and `label` separately. Paths are relative to `brief.yml`.

### AI-Generated Content Display

Books generated with `ligarb write` automatically have `ai_generated: true` set in `book.yml`. This means:

- An "AI Generated" badge is displayed in the sidebar
- A disclaimer text is shown at the bottom of each chapter
- Meta tags are added to suppress search engine indexing and AI crawler training

The footer text can be customized with the `footer` field:

```yaml
ai_generated: true
footer: "AI-generated content. Please verify before relying on it."
```

`footer` can also be used independently of `ai_generated` (e.g., for copyright notices).

### Prerequisites

The [Claude Code](https://claude.com/claude-code) CLI (`claude` command) must be installed.

## Using AI Manually

You can also instruct AI manually without using `ligarb write`.
Pass the output of `ligarb help` to the AI:

```bash
ligarb help
```

This output contains everything the AI needs to create a book: configuration file specs, supported Markdown syntax, available code block types, and more.

### Prompt Examples

#### Create a new book from scratch

```
Read the output of ligarb help and create the following book:
- Topic: Git Getting Started Guide
- Audience: Programming beginners
- Structure: About 5 chapters
- Language: English

Use ligarb init to create a scaffold, then add chapters.
```

#### Turn existing documents into a book

```
Combine the Markdown files in this directory into a book using ligarb.
Read ligarb help, create book.yml, and build with ligarb build.
```

#### Create a book with diagrams and math

```
Read ligarb help and create a book with the following content.
Include architecture diagrams using mermaid.

Topic: Web Application Design Patterns
```

```
Read ligarb help and create an introduction to linear algebra.
Use ```math (KaTeX) for equations.
```

#### Add or edit chapters

```
Read ligarb help and add a "Deployment" chapter to this book.
Register it in book.yml as well.
```

```
Review the content of 03-api.md and add sequence diagrams (mermaid).
```

### Add a translation to an existing book

Sometimes you want to make an English book available to Japanese readers, or add an English version to a Japanese technical document. ligarb's multi-language feature ([](translations.md)) lets you bundle multiple languages into a single HTML with a language switcher.

When asking the AI to do this, tell it to convert the existing `book.yml` into a hub and translate all chapters. Since `ligarb help` includes the spec, the AI can correctly handle `translations`, `inherit`, and other settings.

Adding Japanese to an English book:

```
Read ligarb help and add a Japanese translation to this English book.

Steps:
1. Convert the existing book.yml into a translations hub
   - Keep shared settings (repository, bibliography, etc.) in the hub
   - Move English-specific settings to book.en.yml (add inherit: book.yml)
2. Translate all chapters into Japanese under chapters/ja/
3. Create book.ja.yml (with inherit: book.yml)
4. Build with ligarb build book.yml and verify
```

Adding English to a Japanese book follows the same approach:

```
Read ligarb help and add an English translation to this Japanese book.

Steps:
1. Convert the existing book.yml into a translations hub
   - Keep shared settings in the hub
   - Move Japanese-specific settings to book.ja.yml (add inherit: book.yml)
2. Translate all chapters into English under chapters/en/
3. Create book.en.yml (with inherit: book.yml)
4. Build with ligarb build book.yml and verify
```

#### Build and verify

```
Build with ligarb build. Fix any errors.
```

## Important Notes

> [!WARNING]
> AI-generated content may contain errors. Always review and proofread before publishing.
> Also check the copyright laws in your jurisdiction regarding AI-generated works.

## Key Points

- **Use `ligarb write`**: Write a brief and run it to automate everything from generation to build
- **Pass `ligarb help`**: When using AI manually, this is the most reliable way to make it understand the spec
- **Request diagrams**: Explicitly asking for "mermaid diagrams" or "KaTeX equations" helps the AI use the appropriate code blocks
- **Work incrementally**: Instructing chapter by chapter yields better quality than doing everything at once
