# Introduction

## What is ligarb?

[ligarb](#index) is a CLI tool that generates a single HTML file from multiple [Markdown](#index) files.
It is ideal for organizing information in "book" format, such as software documentation and tutorials.

## Features

### Output

- **Single HTML output**: All chapters are combined into one `index.html`
- **Searchable [table of contents](#index)**: A sidebar TOC with keyword filtering
- **Chapter switching**: JavaScript toggles content by chapter
- **[Permalink](#index) support**: Link directly to a specific chapter via URL `#`
- **[Parts](#index) & [appendices](#index)**: Group chapters into parts and add appendices
- **Previous/Next navigation**: Links to adjacent chapters at the bottom of each chapter
- **[Dark mode](#index)**: Toggle via a button in the sidebar
- **[Custom CSS](#index)**: Apply your own styles
- **[GitHub edit links](#index)**: Show "Edit on GitHub" links for each chapter
- **Responsive design**: Comfortable reading on both desktop and mobile
- **Print support**: All chapters are expanded when printing

### Writing Assistance

- **[AI auto-writing](ai.md)**: Write a brief (`brief.yml`) and run `ligarb write` to automate everything from generation to build
- **[Comment & review](serve.md)**: Select text in `ligarb serve` to comment, and Claude will return improvement suggestions and patches. Approve to auto-apply to source files
- **[Manual AI integration](ai.md)**: Pass the output of `ligarb help` to an AI for accurate spec-aware chapter editing

## Comparison with Similar Tools

Several tools generate books from Markdown. Here is how ligarb compares to some popular ones.

### mdBook

A Rust-based documentation generator used for the official Rust documentation. It generates multi-page output by default. ligarb combines all chapters into a single HTML, so you can share the entire book by passing a single file.

### Honkit (formerly GitBook)

A Node.js-based open-source fork of GitBook. It can produce single-page output but requires a Node.js build environment. ligarb runs with just Ruby and a few gems, and configuration is a single `book.yml`.

### Sphinx

A Python-based documentation generator supporting reStructuredText and Markdown. It is very feature-rich but has a steeper learning curve. ligarb prioritizes simplicity: "write in Markdown, build with one command."

### Pandoc

A universal format converter. It can generate a single HTML from multiple Markdown files, but features like a sidebar TOC, chapter switching, and search must be built separately. ligarb includes all of these out of the box.

### VitePress

A Vue-based static site generator widely used for documentation sites. It offers a dev server with instant preview, Vue component embedding, and SEO-friendly multi-page output — features tailored for public-facing documentation sites. ligarb, on the other hand, specializes in single HTML output that requires no hosting and can be shared by simply passing a file. VitePress is the better choice for public documentation sites where SEO matters; ligarb is ideal for internal manuals and distributable books.

### Where ligarb Fits

ligarb focuses on making it easy to create a book and distribute it as-is. Single HTML output, built-in sidebar TOC and search, and AI integration are available with minimal configuration. For highly customizable output formats and themes, Sphinx or mdBook may be better suited, but when you want to quickly turn your Markdown into a book, ligarb shines.

## About This Manual

This manual itself is built with ligarb.
The following chapters walk you through installation to building your first book.
