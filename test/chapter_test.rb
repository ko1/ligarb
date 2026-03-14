# frozen_string_literal: true

require_relative "test_helper"

class ChapterTest < Minitest::Test
  def make_chapter(content, filename: "01-test.md")
    Dir.mktmpdir do |dir|
      path = File.join(dir, filename)
      File.write(path, content)
      yield Ligarb::Chapter.new(path, dir)
    end
  end

  def test_title_from_h1
    make_chapter("# Hello World\n\nContent") do |ch|
      assert_equal "Hello World", ch.title
    end
  end

  def test_slug_from_filename
    make_chapter("# T", filename: "03-getting-started.md") do |ch|
      assert_equal "03-getting-started", ch.slug
    end
  end

  def test_display_title_without_number
    make_chapter("# Title") do |ch|
      assert_equal "Title", ch.display_title
    end
  end

  def test_display_title_with_number
    make_chapter("# Title") do |ch|
      ch.number = 3
      assert_equal "3. Title", ch.display_title
    end
  end

  def test_display_title_with_appendix_letter
    make_chapter("# Title") do |ch|
      ch.appendix_letter = "B"
      assert_equal "B. Title", ch.display_title
    end
  end

  def test_headings_extraction
    make_chapter("# H1\n## H2\n### H3\n#### H4") do |ch|
      assert_equal 3, ch.headings.size
      assert_equal [1, 2, 3], ch.headings.map(&:level)
    end
  end

  def test_heading_ids_scoped_by_slug
    make_chapter("# Title\n## Section", filename: "ch1.md") do |ch|
      assert_includes ch.html, 'id="ch1--title"'
      assert_includes ch.html, 'id="ch1--section"'
    end
  end

  def test_image_path_rewrite
    make_chapter("![img](images/foo.png)") do |ch|
      assert_includes ch.html, 'src="images/foo.png"'
    end
    make_chapter("![img](sub/dir/bar.png)") do |ch|
      assert_includes ch.html, 'src="images/bar.png"'
    end
    make_chapter("![img](https://example.com/img.png)") do |ch|
      assert_includes ch.html, 'src="https://example.com/img.png"'
    end
  end

  def test_mermaid_conversion
    make_chapter("```mermaid\ngraph TD\n  A-->B\n```") do |ch|
      assert_includes ch.html, '<div class="mermaid">'
      refute_includes ch.html, '<pre>'
    end
  end

  def test_math_conversion
    make_chapter("```math\nE = mc^2\n```") do |ch|
      assert_includes ch.html, '<div class="math-block"'
      assert_includes ch.html, 'data-math='
    end
  end

  def test_footnote_id_scoping
    make_chapter("Text[^1]\n\n[^1]: Note", filename: "ch1.md") do |ch|
      refute_includes ch.html, 'id="fn:1"'
      assert_includes ch.html, "fn:ch1--1"
    end
  end

  def test_cover_flag
    make_chapter("# Cover") do |ch|
      refute ch.cover?
      ch.cover = true
      assert ch.cover?
    end
  end

  def test_part_title_flag
    make_chapter("# Part") do |ch|
      refute ch.part_title?
      ch.part_title = true
      assert ch.part_title?
    end
  end

  def test_relative_path_accessor
    make_chapter("# T") do |ch|
      assert_nil ch.relative_path
      ch.relative_path = "docs/ch1.md"
      assert_equal "docs/ch1.md", ch.relative_path
    end
  end

  # Index tests

  def test_index_basic
    make_chapter("# T\n\n[Ruby](#index) is great.") do |ch|
      assert_equal 1, ch.index_entries.size
      assert_equal "Ruby", ch.index_entries[0].term
      assert_equal "Ruby", ch.index_entries[0].display_text
      refute_includes ch.html, 'href="#index"'
      assert_includes ch.html, '<span id="01-test--idx-0">Ruby</span>'
    end
  end

  def test_index_custom_term
    make_chapter("# T\n\n[dynamic typing](#index:動的型付け)") do |ch|
      assert_equal 1, ch.index_entries.size
      assert_equal "動的型付け", ch.index_entries[0].term
      assert_equal "dynamic typing", ch.index_entries[0].display_text
    end
  end

  def test_index_multiple_terms
    make_chapter("# T\n\n[Ruby](#index:Ruby,プログラミング言語/Ruby)") do |ch|
      assert_equal 2, ch.index_entries.size
      assert_equal "Ruby", ch.index_entries[0].term
      assert_equal "プログラミング言語/Ruby", ch.index_entries[1].term
      # Both share the same anchor
      assert_equal ch.index_entries[0].anchor_id, ch.index_entries[1].anchor_id
    end
  end

  def test_index_no_entries
    make_chapter("# T\n\nNo index markers here.") do |ch|
      assert_empty ch.index_entries
    end
  end
end
