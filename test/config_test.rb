# frozen_string_literal: true

require_relative "test_helper"

class ConfigTest < Minitest::Test
  def with_book(data, files: {})
    Dir.mktmpdir do |dir|
      files.each do |name, content|
        path = File.join(dir, name)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, content)
      end
      File.write(File.join(dir, "book.yml"), YAML.dump(data))
      yield Ligarb::Config.new(File.join(dir, "book.yml"))
    end
  end

  def test_required_fields
    capture_io do
      assert_raises(SystemExit) { with_book({}) { } }
      assert_raises(SystemExit) { with_book({"title" => "T"}) { } }
      assert_raises(SystemExit) { with_book({"chapters" => ["a.md"]}) { } }
    end
  end

  def test_defaults
    with_book({"title" => "T", "chapters" => ["a.md"]}, files: {"a.md" => "# A"}) do |config|
      assert_equal "T", config.title
      assert_equal "", config.author
      assert_equal "en", config.language
      assert_equal "build", config.output_dir
      assert_equal true, config.chapter_numbers
      assert_nil config.style
      assert_nil config.repository
    end
  end

  def test_optional_fields
    data = {
      "title" => "T", "author" => "A", "language" => "ja",
      "output_dir" => "out", "chapter_numbers" => false,
      "style" => "custom.css", "repository" => "https://github.com/x/y",
      "chapters" => ["a.md"],
    }
    with_book(data, files: {"a.md" => "# A"}) do |config|
      assert_equal "A", config.author
      assert_equal "ja", config.language
      assert_equal "out", config.output_dir
      assert_equal false, config.chapter_numbers
      assert_equal "custom.css", config.style
      assert_equal "https://github.com/x/y", config.repository
    end
  end

  def test_simple_structure
    with_book({"title" => "T", "chapters" => ["a.md", "b.md"]}, files: {"a.md" => "# A", "b.md" => "# B"}) do |config|
      assert_equal 2, config.structure.size
      assert_equal :chapter, config.structure[0].type
      assert_equal :chapter, config.structure[1].type
    end
  end

  def test_part_structure
    data = {"title" => "T", "chapters" => [{"part" => "p.md", "chapters" => ["a.md"]}]}
    with_book(data, files: {"p.md" => "# P", "a.md" => "# A"}) do |config|
      assert_equal 1, config.structure.size
      assert_equal :part, config.structure[0].type
      assert_equal 1, config.structure[0].children.size
    end
  end

  def test_cover_structure
    data = {"title" => "T", "chapters" => [{"cover" => "c.md"}, "a.md"]}
    with_book(data, files: {"c.md" => "# C", "a.md" => "# A"}) do |config|
      assert_equal :cover, config.structure[0].type
      assert_equal :chapter, config.structure[1].type
    end
  end

  def test_appendix_structure
    data = {"title" => "T", "chapters" => [{"appendix" => ["a.md"]}]}
    with_book(data, files: {"a.md" => "# A"}) do |config|
      assert_equal :appendix_group, config.structure[0].type
      assert_equal 1, config.structure[0].children.size
    end
  end

  def test_appendix_label
    with_book({"title" => "T", "language" => "ja", "chapters" => ["a.md"]}, files: {"a.md" => "# A"}) do |config|
      assert_equal "付録", config.appendix_label
    end
    with_book({"title" => "T", "language" => "en", "chapters" => ["a.md"]}, files: {"a.md" => "# A"}) do |config|
      assert_equal "Appendix", config.appendix_label
    end
  end
end
