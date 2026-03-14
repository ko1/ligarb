# frozen_string_literal: true

require_relative "version"
require_relative "builder"
require_relative "initializer"

module Ligarb
  module CLI
    module_function

    def run(args)
      command = args.shift

      case command
      when "build"
        config_path = args.first || "book.yml"
        Builder.new(config_path).build
      when "init"
        Initializer.new(args.first).run
      when "--help", "-h", nil
        print_usage
      when "help"
        print_spec
      when "version", "--version", "-v"
        puts "ligarb #{VERSION}"
      else
        $stderr.puts "Unknown command: #{command}"
        $stderr.puts "Run 'ligarb --help' for usage information."
        exit 1
      end
    end

    def print_usage
      puts <<~USAGE
        ligarb #{VERSION} - Generate a single-page HTML book from Markdown files

        Usage:
          ligarb init [DIRECTORY]  Create a new book project
          ligarb build [CONFIG]    Build the HTML book (default CONFIG: book.yml)
          ligarb help              Show detailed specification (for AI integration)
          ligarb version          Show version number

        Options:
          -h, --help              Show this usage summary
          -v, --version           Show version number

        Configuration (book.yml):
          title            (required) Book title
          chapters         (required) Book structure (chapters, parts, appendix)
          author           (optional) Author name (default: "")
          language         (optional) HTML lang attribute (default: "en")
          output_dir       (optional) Output directory (default: "build")
          chapter_numbers  (optional) Show chapter/section numbers (default: true)
          style            (optional) Custom CSS file path (default: none)
          repository       (optional) GitHub repository URL for "Edit on GitHub" links

        Example:
          ligarb build
          ligarb build path/to/book.yml
      USAGE
    end

    def print_spec
      puts <<~SPEC
        ligarb - Generate a single-page HTML book from Markdown files

        Version: #{VERSION}

        == Overview ==

        ligarb converts multiple Markdown files into a self-contained index.html.
        The generated HTML includes:
        - A left sidebar with a searchable table of contents (h1-h3)
        - Chapter-based content switching in the main area
        - Permalink support via URL hash (#chapter-slug)
        - Responsive design with print-friendly styles
        - Syntax-highlighted code blocks
        - Search with content highlighting
        - Chapter and section numbering (configurable)
        - Previous/Next chapter navigation
        - Dark mode toggle (saved to localStorage)
        - Custom CSS support
        - "Edit on GitHub" links (optional)
        - Footnotes (kramdown syntax)

        == Commands ==

        ligarb init [DIRECTORY] Create a new book project with scaffolding.
                                If DIRECTORY is given, creates and populates that directory.
                                If omitted, populates the current directory.
                                Generates book.yml, 01-introduction.md, and images/.
                                If .md files already exist, registers them as chapters.
                                Aborts if book.yml already exists.

        ligarb build [CONFIG]   Build the HTML book.
                                CONFIG defaults to 'book.yml' in the current directory.

        ligarb help             Show this detailed specification.

        ligarb --help           Show short usage summary.

        ligarb version          Show the version number.

        == Configuration: book.yml ==

        The configuration file is a YAML file with the following fields:

        title:           (required) The book title displayed in the header and <title> tag.
        author:          (optional) Author name displayed in the header. Default: empty.
        language:        (optional) HTML lang attribute value. Default: "en".
        output_dir:      (optional) Output directory relative to book.yml. Default: "build".
        chapter_numbers: (optional) Show chapter/section numbers (e.g. "1.", "1.1", "1.1.1").
                         Default: true.
        style:           (optional) Path to a custom CSS file relative to book.yml.
                         Loaded after the default styles, so it can override any rule.
        repository:      (optional) GitHub repository URL (e.g. "https://github.com/user/repo").
                         When set, each chapter shows a "View on GitHub" link.
                         The link points to {repository}/blob/HEAD/{path-from-git-root}.
                         The chapter path is resolved relative to the Git repository root.
        chapters:        (required) Book structure. An array that can contain:
                         - A cover: a centered title/landing page
                         - A string: a chapter Markdown file path (relative to book.yml)
                         - A part: groups chapters under a titled section
                         - An appendix: groups chapters with alphabetic numbering (A, B, C, ...)

        The chapters array supports four element types:

        1. Cover (object with 'cover' key):
               chapters:
                 - cover: cover.md          # Markdown file: displayed as centered title page
                                            # Not shown in the TOC sidebar.

        2. Plain chapter (string):
               chapters:
                 - 01-introduction.md

        3. Part (object with 'part' and 'chapters' keys):
               chapters:
                 - part: part1.md           # Markdown file: h1 = part title, body = opening text
                   chapters:
                     - 01-introduction.md
                     - 02-getting-started.md

        4. Appendix (object with 'appendix' key, value is array of chapter files):
               chapters:
                 - appendix:
                   - a1-references.md
                   - a2-glossary.md

        These can be combined freely:

            chapters:
              - cover: cover.md
              - part: part1.md
                chapters:
                  - 01-introduction.md
                  - 02-getting-started.md
              - part: part2.md
                chapters:
                  - 03-advanced.md
              - appendix:
                - a1-references.md

        Part numbering is sequential across parts (1, 2, 3, ...).
        Appendix numbering uses letters (A, B, C, ...).

        Example book.yml (simple):

            title: "My Software Guide"
            author: "Author Name"
            language: "ja"
            chapters:
              - 01-introduction.md
              - 02-getting-started.md
              - 03-advanced.md

        Example book.yml (with parts and appendix):

            title: "My Software Guide"
            author: "Author Name"
            language: "ja"
            chapters:
              - part: part1.md
                chapters:
                  - 01-introduction.md
                  - 02-getting-started.md
              - part: part2.md
                chapters:
                  - 03-advanced.md
                  - 04-deployment.md
              - appendix:
                - a1-config-reference.md

        == Directory Structure ==

        A typical book project has this structure:

            my-book/
            ├── book.yml              # Configuration file
            ├── part1.md              # Part opening page (optional)
            ├── 01-introduction.md    # Markdown source files
            ├── 02-getting-started.md
            ├── 03-advanced.md
            └── images/               # Image files (optional)
                ├── screenshot.png
                └── diagram.svg

        After running 'ligarb build', the output is:

            my-book/
            └── build/
                ├── index.html        # Single-page HTML book
                ├── js/               # Auto-downloaded (only if needed)
                ├── css/              # Auto-downloaded (only if needed)
                └── images/           # Copied image files

        == Markdown Files ==

        Each Markdown file represents one chapter. ligarb uses GitHub Flavored
        Markdown (GFM) via kramdown. Supported syntax includes:

        - Headings (# h1, ## h2, ### h3) — used for TOC generation
        - Code blocks with language-specific syntax highlighting (``` fenced blocks)
        - Tables, task lists, strikethrough, and other GFM extensions
        - Inline HTML

        The first heading (h1) in each file becomes the chapter title in the TOC.

        == Fenced Code Blocks ==

        The following fenced code block types are automatically detected and
        rendered. Required JS/CSS is auto-downloaded on first build to build/js/
        and build/css/.

        ```ruby, ```python, etc.   Syntax highlighting (highlight.js, BSD-3-Clause)
        ```mermaid                  Diagrams: flowcharts, sequence, class, etc.
                                    (mermaid, MIT)
        ```math                     LaTeX math equations (KaTeX, MIT)

        These are rendered visually in the output HTML — use them freely.

        Mermaid example (flowchart):

            ```mermaid
            graph TD
                A[Start] --> B{Check}
                B -->|Yes| C[OK]
                B -->|No| D[Retry]
            ```

        Mermaid example (sequence diagram):

            ```mermaid
            sequenceDiagram
                Client->>Server: Request
                Server-->>Client: Response
            ```

        Math example (KaTeX, LaTeX syntax):

            ```math
            E = mc^2
            ```

        == Images ==

        Place image files in the 'images/' directory next to book.yml.
        Reference them from Markdown with relative paths:

            ![Screenshot](images/screenshot.png)

        ligarb rewrites image paths to 'images/filename' in the output and copies
        all files from the images/ directory to the output.

        == Build ==

        Run from the directory containing book.yml:

            ligarb build

        Or specify a path to book.yml:

            ligarb build path/to/book.yml

        The generated index.html is a fully self-contained HTML file (CSS and JS
        are embedded). Open it directly in a browser — no web server needed.

        == Footnotes ==

        Footnotes use kramdown syntax:

            This is a sentence with a footnote[^1].

            [^1]: This is the footnote content.

        Footnote IDs are scoped per chapter to avoid collisions in the single-page
        output.

        == Index ==

        Mark terms for the book index using Markdown link syntax with #index:

            [Ruby](#index)                           Index the link text as-is
            [dynamic typing](#index:動的型付け)       Index under a specific term
            [Ruby](#index:Ruby,Languages/Ruby)       Multiple index entries (comma-separated)
            [Ruby](#index:Languages/Ruby)            Hierarchical: Languages > Ruby

        The link is rendered as plain text in the output (no link styling).
        An "Index" section is automatically appended at the end of the book,
        with terms sorted alphabetically and grouped by first character.

        Clicking an index entry navigates to the exact location in the chapter.

        == Custom CSS ==

        Add a 'style' field to book.yml to inject custom CSS:

            style: "custom.css"

        The custom CSS is loaded after the default styles. You can override any
        CSS custom property (e.g. colors, fonts, sidebar width) or add new rules.

        Example custom.css:

            :root {
              --color-accent: #e63946;
              --sidebar-width: 320px;
            }

        == Dark Mode ==

        The generated HTML includes a dark mode toggle button (moon icon) in the
        sidebar header. The user's preference is saved to localStorage and persists
        across page reloads.

        Custom CSS can override dark mode colors using the [data-theme="dark"]
        selector.

        == Edit on GitHub ==

        Add a 'repository' field to book.yml:

            repository: "https://github.com/user/repo"

        Each chapter will show a "View on GitHub" link pointing to:
        {repository}/blob/HEAD/{path-from-git-root}

        == Previous/Next Navigation ==

        Each chapter displays Previous and Next navigation links at the bottom.
        These follow the flat chapter order (including across parts and appendix).
        Part title pages do not show navigation.
      SPEC
    end
  end
end
