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
      Ligarb::Builder.new(File.join(dir, "book.yml")).build
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
end
