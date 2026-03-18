# frozen_string_literal: true

require_relative "test_helper"

class BuilderTest < Minitest::Test
  def build_book(data, files: {})
    Dir.mktmpdir do |dir|
      files.each do |name, content|
        path = File.join(dir, name)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, content)
      end
      File.write(File.join(dir, "book.yml"), YAML.dump(data))
      capture_io { Ligarb::Builder.new(File.join(dir, "book.yml")).build }
      yield dir
    end
  end

  def test_simple_build
    data = {"title" => "Test", "chapters" => ["ch1.md"]}
    build_book(data, files: {"ch1.md" => "# Chapter 1\n\nHello"}) do |dir|
      output = File.join(dir, "build", "index.html")
      assert File.exist?(output)
      html = File.read(output)
      assert_includes html, "Chapter 1"
      assert_includes html, "Hello"
    end
  end

  def test_part_build
    data = {"title" => "Test", "chapters" => [
      {"part" => "p.md", "chapters" => ["ch1.md"]},
    ]}
    build_book(data, files: {"p.md" => "# Part 1\n\nIntro", "ch1.md" => "# Ch"}) do |dir|
      html = File.read(File.join(dir, "build", "index.html"))
      assert_includes html, "Part 1"
      assert_includes html, "toc-part-title"
    end
  end

  def test_cover_build
    data = {"title" => "Test", "chapters" => [
      {"cover" => "cover.md"}, "ch1.md",
    ]}
    build_book(data, files: {"cover.md" => "# Welcome", "ch1.md" => "# Ch"}) do |dir|
      html = File.read(File.join(dir, "build", "index.html"))
      assert_includes html, "Welcome"
      # Cover should not be in TOC
      refute_includes html, 'class="toc-chapter" data-chapter="cover"'
    end
  end

  def test_appendix_build
    data = {"title" => "Test", "chapters" => [
      "ch1.md", {"appendix" => ["ap.md"]},
    ]}
    build_book(data, files: {"ch1.md" => "# Ch", "ap.md" => "# Ref"}) do |dir|
      html = File.read(File.join(dir, "build", "index.html"))
      assert_includes html, "A. Ref"
      assert_includes html, "toc-appendix-title"
    end
  end

  def test_chapter_numbering
    data = {"title" => "Test", "chapters" => ["ch1.md", "ch2.md"]}
    build_book(data, files: {"ch1.md" => "# First", "ch2.md" => "# Second"}) do |dir|
      html = File.read(File.join(dir, "build", "index.html"))
      assert_includes html, "1. First"
      assert_includes html, "2. Second"
    end
  end

  def test_custom_css
    data = {"title" => "Test", "style" => "my.css", "chapters" => ["ch1.md"]}
    build_book(data, files: {"ch1.md" => "# Ch", "my.css" => ".custom { color: red; }"}) do |dir|
      html = File.read(File.join(dir, "build", "index.html"))
      assert_includes html, ".custom { color: red; }"
    end
  end

  def test_repository_link
    data = {"title" => "Test", "repository" => "https://github.com/x/y", "chapters" => ["ch1.md"]}
    build_book(data, files: {"ch1.md" => "# Ch"}) do |dir|
      html = File.read(File.join(dir, "build", "index.html"))
      assert_includes html, "View on GitHub"
      assert_includes html, "https://github.com/x/y/blob/HEAD/"
    end
  end

  def test_dark_mode_toggle
    data = {"title" => "Test", "chapters" => ["ch1.md"]}
    build_book(data, files: {"ch1.md" => "# Ch"}) do |dir|
      html = File.read(File.join(dir, "build", "index.html"))
      assert_includes html, "theme-toggle"
      assert_includes html, "ligarb-theme"
    end
  end

  def test_prev_next_nav
    data = {"title" => "Test", "chapters" => ["ch1.md", "ch2.md"]}
    build_book(data, files: {"ch1.md" => "# First", "ch2.md" => "# Second"}) do |dir|
      html = File.read(File.join(dir, "build", "index.html"))
      assert_includes html, "nav-next"
      assert_includes html, "nav-prev"
    end
  end

  def test_images_copied
    data = {"title" => "Test", "chapters" => ["ch1.md"]}
    files = {"ch1.md" => "# Ch\n![img](images/pic.png)", "images/pic.png" => "PNG"}
    build_book(data, files: files) do |dir|
      assert File.exist?(File.join(dir, "build", "images", "pic.png"))
    end
  end

  def test_cross_reference
    data = {"title" => "Test", "chapters" => ["ch1.md", "ch2.md"]}
    files = {
      "ch1.md" => "# First\n\nSee [second chapter](ch2.md) and [setup](ch2.md#Setup).",
      "ch2.md" => "# Second\n\n## Setup\n\nContent"
    }
    build_book(data, files: files) do |dir|
      html = File.read(File.join(dir, "build", "index.html"))
      assert_includes html, 'href="#ch2"'
      assert_includes html, 'href="#ch2--setup"'
      assert_includes html, ">second chapter</a>"
      assert_includes html, ">setup</a>"
    end
  end

  def test_cross_reference_auto_text
    data = {"title" => "Test", "chapters" => ["ch1.md", "ch2.md"]}
    files = {
      "ch1.md" => "# First\n\nSee [](ch2.md) and [](ch2.md#Details).",
      "ch2.md" => "# Second\n\n## Details\n\nContent"
    }
    build_book(data, files: files) do |dir|
      html = File.read(File.join(dir, "build", "index.html"))
      assert_includes html, ">2. Second</a>"
      assert_includes html, ">2.1 Details</a>"
    end
  end

  def test_bibliography_basic
    refs = {"matz1995" => {"author" => "Yukihiro Matsumoto", "title" => "The Ruby Programming Language", "year" => 1995, "url" => "https://www.ruby-lang.org"}}
    data = {"title" => "Test", "bibliography" => "refs.yml", "chapters" => ["ch1.md"]}
    files = {
      "ch1.md" => "# Ch\n\n[Ruby](#cite:matz1995) is great.",
      "refs.yml" => YAML.dump(refs),
    }
    build_book(data, files: files) do |dir|
      html = File.read(File.join(dir, "build", "index.html"))
      # Citation in text
      assert_includes html, 'class="cite-ref"'
      assert_includes html, 'href="#bib-matz1995"'
      assert_includes html, "[Yukihiro, 1995]"
      # Bibliography section
      assert_includes html, 'id="bib-matz1995"'
      assert_includes html, "The Ruby Programming Language"
      assert_includes html, "__bibliography__"
    end
  end

  def test_bibliography_no_entries
    data = {"title" => "Test", "chapters" => ["ch1.md"]}
    build_book(data, files: {"ch1.md" => "# Ch\n\nNo citations."}) do |dir|
      html = File.read(File.join(dir, "build", "index.html"))
      refute_includes html, "__bibliography__"
      refute_includes html, "bibliography-chapter"
    end
  end

  def test_bibliography_unknown_key
    refs = {"matz1995" => {"author" => "Matsumoto", "title" => "Ruby", "year" => 1995}}
    data = {"title" => "Test", "bibliography" => "refs.yml", "chapters" => ["ch1.md"]}
    files = {
      "ch1.md" => "# Ch\n\n[text](#cite:unknown_key)",
      "refs.yml" => YAML.dump(refs),
    }
    assert_raises(SystemExit) do
      build_book(data, files: files) { |_dir| }
    end
  end

  def test_bibliography_url_linked
    refs = {"book1" => {"author" => "Author", "title" => "Title", "year" => 2020, "url" => "https://example.com"}}
    data = {"title" => "Test", "bibliography" => "refs.yml", "chapters" => ["ch1.md"]}
    files = {
      "ch1.md" => "# Ch\n\n[text](#cite:book1)",
      "refs.yml" => YAML.dump(refs),
    }
    build_book(data, files: files) do |dir|
      html = File.read(File.join(dir, "build", "index.html"))
      assert_includes html, 'href="https://example.com"'
      assert_includes html, "<em><a"
    end
  end

  def test_bibliography_bibtex
    bib = <<~BIB
      @book{matz1995,
        author = {Yukihiro Matsumoto},
        title = {The Ruby Programming Language},
        year = {1995},
        publisher = {O'Reilly},
        url = {https://www.ruby-lang.org}
      }
    BIB
    data = {"title" => "Test", "bibliography" => "refs.bib", "chapters" => ["ch1.md"]}
    files = {
      "ch1.md" => "# Ch\n\n[Ruby](#cite:matz1995) is great.",
      "refs.bib" => bib,
    }
    build_book(data, files: files) do |dir|
      html = File.read(File.join(dir, "build", "index.html"))
      assert_includes html, 'href="#bib-matz1995"'
      assert_includes html, "[Yukihiro, 1995]"
      assert_includes html, 'id="bib-matz1995"'
      assert_includes html, "The Ruby Programming Language"
      assert_includes html, "O'Reilly"
    end
  end

  def test_bibliography_bibtex_article
    bib = <<~BIB
      @article{knuth1984,
        author = {Donald Knuth},
        title = {Literate Programming},
        year = {1984},
        journal = {The Computer Journal},
        volume = {27},
        number = {2},
        pages = {97-111}
      }
    BIB
    data = {"title" => "Test", "bibliography" => "refs.bib", "chapters" => ["ch1.md"]}
    files = {
      "ch1.md" => "# Ch\n\n[LP](#cite:knuth1984) is great.",
      "refs.bib" => bib,
    }
    build_book(data, files: files) do |dir|
      html = File.read(File.join(dir, "build", "index.html"))
      assert_includes html, "Literate Programming"
      assert_includes html, "<em>The Computer Journal</em>"
      assert_includes html, "27(2)"
      assert_includes html, "pp. 97-111"
    end
  end

  def test_bibliography_extended_fields
    refs = {
      "book1" => {
        "author" => "Author Name",
        "title" => "Great Book",
        "year" => 2020,
        "publisher" => "Acme Press",
        "edition" => "2nd ed.",
        "doi" => "10.1234/example",
        "url" => "https://example.com",
      }
    }
    data = {"title" => "Test", "bibliography" => "refs.yml", "chapters" => ["ch1.md"]}
    files = {
      "ch1.md" => "# Ch\n\n[text](#cite:book1)",
      "refs.yml" => YAML.dump(refs),
    }
    build_book(data, files: files) do |dir|
      html = File.read(File.join(dir, "build", "index.html"))
      assert_includes html, "Acme Press"
      assert_includes html, "2nd ed."
      assert_includes html, "https://doi.org/10.1234/example"
    end
  end

  def test_bibliography_bibtex_comment
    bib = <<~BIB
      % This is a comment
      @book{key1,
        author = {Author},
        title = {Title},
        year = {2020}
      }
    BIB
    data = {"title" => "Test", "bibliography" => "refs.bib", "chapters" => ["ch1.md"]}
    files = {
      "ch1.md" => "# Ch\n\n[text](#cite:key1)",
      "refs.bib" => bib,
    }
    build_book(data, files: files) do |dir|
      html = File.read(File.join(dir, "build", "index.html"))
      assert_includes html, 'id="bib-key1"'
      assert_includes html, "Title"
    end
  end

  def test_bibliography_bibtex_nested_braces
    bib = <<~BIB
      @book{key1,
        author = {Author},
        title = {The {Ruby} Language},
        year = {2020}
      }
    BIB
    data = {"title" => "Test", "bibliography" => "refs.bib", "chapters" => ["ch1.md"]}
    files = {
      "ch1.md" => "# Ch\n\n[text](#cite:key1)",
      "refs.bib" => bib,
    }
    build_book(data, files: files) do |dir|
      html = File.read(File.join(dir, "build", "index.html"))
      assert_includes html, "The Ruby Language"
    end
  end

  def test_cross_reference_missing_target
    data = {"title" => "Test", "chapters" => ["ch1.md"]}
    files = {"ch1.md" => "# Ch\n\n[link](missing.md)"}
    assert_raises(Ligarb::Chapter::CrossReferenceError) do
      build_book(data, files: files) { |_dir| }
    end
  end
end
