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

  # Admonition tests

  def test_admonition_note
    make_chapter("# T\n\n> [!NOTE]\n> This is a note.") do |ch|
      assert_includes ch.html, '<div class="admonition admonition-note">'
      assert_includes ch.html, '<p class="admonition-title">Note</p>'
      assert_includes ch.html, "This is a note."
      refute_includes ch.html, "<blockquote>"
    end
  end

  def test_admonition_all_types
    %w[NOTE TIP WARNING CAUTION IMPORTANT].each do |type|
      make_chapter("# T\n\n> [!#{type}]\n> Content.") do |ch|
        assert_includes ch.html, "admonition-#{type.downcase}", "Expected admonition-#{type.downcase}"
        refute_includes ch.html, "<blockquote>"
      end
    end
  end

  def test_admonition_multiple_paragraphs
    md = "# T\n\n> [!WARNING]\n> First paragraph.\n>\n> Second paragraph."
    make_chapter(md) do |ch|
      assert_includes ch.html, "admonition-warning"
      assert_includes ch.html, "First paragraph."
      assert_includes ch.html, "Second paragraph."
    end
  end

  def test_normal_blockquote_not_converted
    make_chapter("# T\n\n> Just a regular quote.") do |ch|
      assert_includes ch.html, "<blockquote>"
      refute_includes ch.html, "admonition"
    end
  end

  def test_index_no_entries
    make_chapter("# T\n\nNo index markers here.") do |ch|
      assert_empty ch.index_entries
    end
  end

  # Cross-reference tests

  def test_cross_reference_with_text
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "ch1.md"), "# Intro\n\nSee [config chapter](ch2.md).")
      File.write(File.join(dir, "ch2.md"), "# Config\n\n## Setup\n\nContent")
      ch1 = Ligarb::Chapter.new(File.join(dir, "ch1.md"), dir)
      ch2 = Ligarb::Chapter.new(File.join(dir, "ch2.md"), dir)

      chapter_map = {
        File.join(dir, "ch2.md") => {
          slug: ch2.slug, chapter: ch2,
          headings: ch2.headings.each_with_object({}) { |h, m| m[h.id] = h }
        }
      }
      ch1.resolve_cross_references!(chapter_map)
      assert_includes ch1.html, '<a href="#ch2">config chapter</a>'
    end
  end

  def test_cross_reference_with_heading
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "ch1.md"), "# Intro\n\nSee [setup](ch2.md#Setup).")
      File.write(File.join(dir, "ch2.md"), "# Config\n\n## Setup\n\nContent")
      ch1 = Ligarb::Chapter.new(File.join(dir, "ch1.md"), dir)
      ch2 = Ligarb::Chapter.new(File.join(dir, "ch2.md"), dir)

      chapter_map = {
        File.join(dir, "ch2.md") => {
          slug: ch2.slug, chapter: ch2,
          headings: ch2.headings.each_with_object({}) { |h, m| m[h.id] = h }
        }
      }
      ch1.resolve_cross_references!(chapter_map)
      assert_includes ch1.html, '<a href="#ch2--setup">setup</a>'
    end
  end

  def test_cross_reference_auto_text_chapter
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "ch1.md"), "# Intro\n\nSee [](ch2.md).")
      File.write(File.join(dir, "ch2.md"), "# Config Guide\n\nContent")
      ch1 = Ligarb::Chapter.new(File.join(dir, "ch1.md"), dir)
      ch2 = Ligarb::Chapter.new(File.join(dir, "ch2.md"), dir)
      ch2.number = 3

      chapter_map = {
        File.join(dir, "ch2.md") => {
          slug: ch2.slug, chapter: ch2,
          headings: ch2.headings.each_with_object({}) { |h, m| m[h.id] = h }
        }
      }
      ch1.resolve_cross_references!(chapter_map)
      assert_includes ch1.html, '<a href="#ch2">3. Config Guide</a>'
    end
  end

  def test_cross_reference_auto_text_heading
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "ch1.md"), "# Intro\n\nSee [](ch2.md#Setup).")
      File.write(File.join(dir, "ch2.md"), "# Config\n\n## Setup\n\nContent")
      ch1 = Ligarb::Chapter.new(File.join(dir, "ch1.md"), dir)
      ch2 = Ligarb::Chapter.new(File.join(dir, "ch2.md"), dir)
      ch2.number = 2

      chapter_map = {
        File.join(dir, "ch2.md") => {
          slug: ch2.slug, chapter: ch2,
          headings: ch2.headings.each_with_object({}) { |h, m| m[h.id] = h }
        }
      }
      ch1.resolve_cross_references!(chapter_map)
      assert_includes ch1.html, '<a href="#ch2--setup">2.1 Setup</a>'
    end
  end

  def test_cross_reference_missing_chapter
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "ch1.md"), "# Intro\n\nSee [x](missing.md).")
      ch1 = Ligarb::Chapter.new(File.join(dir, "ch1.md"), dir)

      assert_raises(Ligarb::Chapter::CrossReferenceError) do
        ch1.resolve_cross_references!({})
      end
    end
  end

  def test_cross_reference_missing_heading
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "ch1.md"), "# Intro\n\nSee [x](ch2.md#nonexistent).")
      File.write(File.join(dir, "ch2.md"), "# Config\n\nContent")
      ch1 = Ligarb::Chapter.new(File.join(dir, "ch1.md"), dir)
      ch2 = Ligarb::Chapter.new(File.join(dir, "ch2.md"), dir)

      chapter_map = {
        File.join(dir, "ch2.md") => {
          slug: ch2.slug, chapter: ch2,
          headings: ch2.headings.each_with_object({}) { |h, m| m[h.id] = h }
        }
      }
      assert_raises(Ligarb::Chapter::CrossReferenceError) do
        ch1.resolve_cross_references!(chapter_map)
      end
    end
  end

  # Inline math tests

  def test_inline_math_basic
    make_chapter("# T\n\nThe formula $E = mc^2$ is famous.") do |ch|
      assert_includes ch.html, 'class="math-inline"'
      assert_includes ch.html, 'data-math="E = mc^2"'
    end
  end

  def test_inline_math_not_in_code
    make_chapter("# T\n\nUse `$x$` in code.") do |ch|
      refute_includes ch.html, 'class="math-inline"'
      assert_includes ch.html, "<code>$x$</code>"
    end
  end

  def test_inline_math_not_in_pre
    make_chapter("# T\n\n```\n$x$\n```") do |ch|
      refute_includes ch.html, 'class="math-inline"'
    end
  end

  def test_inline_math_not_dollar_amount
    make_chapter("# T\n\nIt costs $10 or more.") do |ch|
      refute_includes ch.html, 'class="math-inline"'
    end
  end

  def test_inline_math_not_double_dollar
    make_chapter("# T\n\nUse $$x$$ for display.") do |ch|
      refute_includes ch.html, 'class="math-inline"'
    end
  end

  def test_inline_math_entities_decoded
    make_chapter("# T\n\nFormula $a &lt; b$ here.") do |ch|
      assert_includes ch.html, 'data-math="a &lt; b"'
    end
  end

  # Citation tests

  def test_cite_basic
    make_chapter("# T\n\n[Ruby](#cite:matz1995) is great.") do |ch|
      assert_equal 1, ch.cite_entries.size
      assert_equal "matz1995", ch.cite_entries[0].key
      assert_equal "Ruby", ch.cite_entries[0].display_text
      assert_equal "01-test", ch.cite_entries[0].chapter_slug
      assert_equal "01-test--cite-0", ch.cite_entries[0].anchor_id
      refute_includes ch.html, 'href="#cite:'
      assert_includes ch.html, '<span id="01-test--cite-0" data-cite-key="matz1995">Ruby</span>'
    end
  end

  def test_cite_multiple
    make_chapter("# T\n\n[Ruby](#cite:matz1995) and [Python](#cite:vanrossum1991).") do |ch|
      assert_equal 2, ch.cite_entries.size
      assert_equal "matz1995", ch.cite_entries[0].key
      assert_equal "vanrossum1991", ch.cite_entries[1].key
      assert_equal "01-test--cite-0", ch.cite_entries[0].anchor_id
      assert_equal "01-test--cite-1", ch.cite_entries[1].anchor_id
    end
  end

  def test_cite_no_entries
    make_chapter("# T\n\nNo citations here.") do |ch|
      assert_empty ch.cite_entries
    end
  end

  def test_cross_reference_external_url_not_rewritten
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "ch1.md"), "# T\n\n[link](https://example.com/foo.md)")
      ch1 = Ligarb::Chapter.new(File.join(dir, "ch1.md"), dir)
      ch1.resolve_cross_references!({})
      assert_includes ch1.html, 'href="https://example.com/foo.md"'
    end
  end
end
