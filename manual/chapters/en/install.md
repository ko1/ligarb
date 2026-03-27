# Installation and Setup

## Requirements

To use ligarb, you need:

- [Ruby](#index) 3.0 or later
- [Bundler](#index) (gem install bundler)

## Installation

Clone the ligarb repository and install dependencies:

```bash
git clone https://github.com/ko1/ligarb.git
cd ligarb
bundle install
```

## Checking the Help

Once installed, check the usage with the [`ligarb help`](#index:ligarb help) command:

```bash
ligarb help
```

All commands and configuration options are displayed. Refer to this command first whenever you have questions.

## Creating a Project

Create a book project with the following directory structure:

```
my-book/
├── book.yml
├── chapters/
│   ├── 01-first-chapter.md
│   └── 02-second-chapter.md
└── images/          # if you have images
    └── screenshot.png
```

[`book.yml`](#index:book.yml) is the configuration file, and Markdown files for each chapter go under `chapters/`.
