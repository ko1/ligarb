# frozen_string_literal: true

require_relative "test_helper"

class TranslationsTest < Minitest::Test
  def setup_translations(dir, hub: {}, langs: {})
    # Write hub book.yml
    File.write(File.join(dir, "book.yml"), YAML.dump(hub))

    # Write per-language configs and chapters
    langs.each do |lang, data|
      config_file = data[:config_file] || "book.#{lang}.yml"
      File.write(File.join(dir, config_file), YAML.dump(data[:config]))
      (data[:files] || {}).each do |name, content|
        path = File.join(dir, name)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, content)
      end
    end
  end

  def test_translations_hub_config
    Dir.mktmpdir do |dir|
      setup_translations(dir,
        hub: {
          "repository" => "https://github.com/x/y",
          "translations" => {"ja" => "book.ja.yml", "en" => "book.en.yml"},
        },
        langs: {
          "ja" => {
            config: {"title" => "テスト本", "language" => "ja", "chapters" => ["ja.md"]},
            files: {"ja.md" => "# はじめに"},
          },
          "en" => {
            config: {"title" => "Test Book", "language" => "en", "chapters" => ["en.md"]},
            files: {"en.md" => "# Introduction"},
          },
        }
      )

      config = Ligarb::Config.new(File.join(dir, "book.yml"))
      assert config.translations_hub?
      assert_equal 2, config.translations.size
      assert_equal "ja", config.translations[0].lang
      assert_equal "テスト本", config.translations[0].title
      assert_equal "en", config.translations[1].lang
      assert_equal "Test Book", config.translations[1].title
    end
  end

  def test_translations_hub_inherits_settings
    Dir.mktmpdir do |dir|
      setup_translations(dir,
        hub: {
          "repository" => "https://github.com/x/y",
          "ai_generated" => true,
          "translations" => {"ja" => "book.ja.yml"},
        },
        langs: {
          "ja" => {
            config: {"title" => "テスト", "language" => "ja", "chapters" => ["ch.md"]},
            files: {"ch.md" => "# Ch"},
          },
        }
      )

      hub_data = YAML.safe_load_file(File.join(dir, "book.yml"))
      child = Ligarb::Config.new(File.join(dir, "book.ja.yml"), parent_data: hub_data)
      assert_equal "https://github.com/x/y", child.repository
      assert_equal true, child.ai_generated
    end
  end

  def test_translations_hub_child_overrides_parent
    Dir.mktmpdir do |dir|
      setup_translations(dir,
        hub: {
          "repository" => "https://github.com/x/y",
          "translations" => {"ja" => "book.ja.yml"},
        },
        langs: {
          "ja" => {
            config: {
              "title" => "テスト",
              "language" => "ja",
              "repository" => "https://github.com/a/b",
              "chapters" => ["ch.md"],
            },
            files: {"ch.md" => "# Ch"},
          },
        }
      )

      hub_data = YAML.safe_load_file(File.join(dir, "book.yml"))
      child = Ligarb::Config.new(File.join(dir, "book.ja.yml"), parent_data: hub_data)
      assert_equal "https://github.com/a/b", child.repository
    end
  end

  def test_translations_hub_build_single_file
    Dir.mktmpdir do |dir|
      setup_translations(dir,
        hub: {
          "translations" => {"ja" => "book.ja.yml", "en" => "book.en.yml"},
        },
        langs: {
          "ja" => {
            config: {"title" => "テスト本", "language" => "ja", "chapters" => ["ja.md"]},
            files: {"ja.md" => "# はじめに\n\n日本語の内容"},
          },
          "en" => {
            config: {"title" => "Test Book", "language" => "en", "chapters" => ["en.md"]},
            files: {"en.md" => "# Introduction\n\nEnglish content"},
          },
        }
      )

      capture_io { Ligarb::Builder.new(File.join(dir, "book.yml")).build }

      # Single output file containing both languages
      output = File.join(dir, "build", "index.html")
      assert File.exist?(output), "Build output should exist"

      html = File.read(output)
      # Both languages' content should be in the same file
      assert_includes html, "はじめに"
      assert_includes html, "日本語の内容"
      assert_includes html, "Introduction"
      assert_includes html, "English content"
    end
  end

  def test_translations_language_switcher_in_html
    Dir.mktmpdir do |dir|
      setup_translations(dir,
        hub: {
          "translations" => {"ja" => "book.ja.yml", "en" => "book.en.yml"},
        },
        langs: {
          "ja" => {
            config: {"title" => "テスト本", "language" => "ja", "chapters" => ["ja.md"]},
            files: {"ja.md" => "# はじめに"},
          },
          "en" => {
            config: {"title" => "Test Book", "language" => "en", "chapters" => ["en.md"]},
            files: {"en.md" => "# Introduction"},
          },
        }
      )

      capture_io { Ligarb::Builder.new(File.join(dir, "book.yml")).build }

      html = File.read(File.join(dir, "build", "index.html"))
      # Language switcher buttons
      assert_includes html, '<div class="lang-switcher">'
      assert_includes html, 'switchLang('
      assert_includes html, 'data-lang="ja"'
      assert_includes html, 'data-lang="en"'
      assert_includes html, ">JA</button>"
      assert_includes html, ">EN</button>"
      # Chapter sections with data-lang
      assert_includes html, 'id="chapter-ja--ja"'
      assert_includes html, 'id="chapter-en--en"'
      # JS lang chapters object
      assert_includes html, "langChapters"
    end
  end

  def test_translations_slug_prefixed
    Dir.mktmpdir do |dir|
      setup_translations(dir,
        hub: {
          "translations" => {"ja" => "book.ja.yml", "en" => "book.en.yml"},
        },
        langs: {
          "ja" => {
            config: {"title" => "テスト本", "language" => "ja", "chapters" => ["ch.md"]},
            files: {"ch.md" => "# タイトル\n\n## セクション"},
          },
          "en" => {
            config: {"title" => "Test Book", "language" => "en", "chapters" => ["ch.md"]},
            files: {"ch.md" => "# Title\n\n## Section"},
          },
        }
      )

      capture_io { Ligarb::Builder.new(File.join(dir, "book.yml")).build }

      html = File.read(File.join(dir, "build", "index.html"))
      # Both languages' chapters have unique prefixed slugs
      assert_includes html, 'id="chapter-ja--ch"'
      assert_includes html, 'id="chapter-en--ch"'
    end
  end

  def test_single_language_no_switcher
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "book.yml"), YAML.dump(
        "title" => "Test", "chapters" => ["ch.md"]
      ))
      File.write(File.join(dir, "ch.md"), "# Ch")

      capture_io { Ligarb::Builder.new(File.join(dir, "book.yml")).build }

      html = File.read(File.join(dir, "build", "index.html"))
      refute_includes html, '<div class="lang-switcher">'
    end
  end

  def test_standalone_child_build
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "book.ja.yml"), YAML.dump(
        "title" => "テスト", "language" => "ja", "chapters" => ["ch.md"]
      ))
      File.write(File.join(dir, "ch.md"), "# はじめに")

      capture_io { Ligarb::Builder.new(File.join(dir, "book.ja.yml")).build }

      html = File.read(File.join(dir, "build", "index.html"))
      assert_includes html, "はじめに"
      refute_includes html, '<div class="lang-switcher">'
    end
  end
end
