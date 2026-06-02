# frozen_string_literal: true

require_relative "test_helper"

# Tests for the public "Report as issue" feedback UI (github_review).
class FeedbackTest < Minitest::Test
  # Builds a book in a tmpdir (no git → relative_path is base-dir relative) and
  # returns [html, stdout, stderr].
  def build_book(data, files: {"ch1.md" => "# Chapter 1\n\nHello"})
    html = nil
    out, err = capture_io do
      Dir.mktmpdir do |dir|
        files.each do |name, content|
          path = File.join(dir, name)
          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, content)
        end
        File.write(File.join(dir, "book.yml"), YAML.dump(data))
        Ligarb::Builder.new(File.join(dir, "book.yml")).build
        html = File.read(File.join(dir, "build", "index.html"))
      end
    end
    [html, out, err]
  end

  def enabled_book(extra = {})
    {
      "title" => "T",
      "repository" => "https://github.com/alice/mybook",
      "github_review" => {"enabled" => true}.merge(extra),
      "chapters" => ["ch1.md"],
    }
  end

  def test_enabled_injects_ui_and_metadata
    html, = build_book(enabled_book)
    assert_includes html, 'data-src-file="ch1.md"'
    assert_includes html, 'data-src-title="1. Chapter 1"'
    assert_includes html, "window._ligarbReview"
    # feedback.js / feedback.css markers
    assert_includes html, "Report as issue"
    assert_includes html, "ligarb-fb-panel"
  end

  def test_config_blob_has_base_template_and_labels
    html, = build_book(enabled_book)
    m = html.match(/window\._ligarbReview = (\{.*?\});/)
    refute_nil m, "expected an injected _ligarbReview config blob"
    cfg = JSON.parse(m[1])
    assert_equal "https://github.com/alice/mybook", cfg["base"]
    assert_equal "book-feedback.yml", cfg["issueTemplate"]
    assert_equal ["feedback"], cfg["labels"]
  end

  def test_custom_template_and_labels_respected
    html, = build_book(enabled_book("issue_template" => "custom.yml", "labels" => %w[feedback reader]))
    cfg = JSON.parse(html.match(/window\._ligarbReview = (\{.*?\});/)[1])
    assert_equal "custom.yml", cfg["issueTemplate"]
    assert_equal %w[feedback reader], cfg["labels"]
  end

  def test_disabled_by_default
    html, = build_book({"title" => "T", "repository" => "https://github.com/a/b", "chapters" => ["ch1.md"]})
    refute_includes html, "data-src-file"
    refute_includes html, "window._ligarbReview"
    refute_includes html, "Report as issue"
  end

  def test_enabled_false_does_not_inject
    data = {"title" => "T", "repository" => "https://github.com/a/b",
            "github_review" => {"enabled" => false}, "chapters" => ["ch1.md"]}
    html, = build_book(data)
    refute_includes html, "data-src-file"
    refute_includes html, "window._ligarbReview"
  end

  def test_missing_repository_warns_and_skips
    data = {"title" => "T", "github_review" => {"enabled" => true}, "chapters" => ["ch1.md"]}
    html, _out, err = build_book(data)
    assert_match(/Warning:.*repository.*not set/, err)
    refute_includes html, "data-src-file"
    refute_includes html, "window._ligarbReview"
  end

  def test_data_src_file_matches_nested_source_path
    data = enabled_book
    data["chapters"] = ["chapters/intro.md"]
    html, = build_book(data, files: {"chapters/intro.md" => "# Intro\n\nText"})
    assert_includes html, 'data-src-file="chapters/intro.md"'
  end

  def test_invalid_github_review_type_aborts
    capture_io do
      assert_raises(SystemExit) do
        build_book({"title" => "T", "github_review" => "yes", "chapters" => ["ch1.md"]})
      end
    end
  end

  # ── Config-level accessors ──

  def test_config_accessors_defaults
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "ch1.md"), "# C")
      File.write(File.join(dir, "book.yml"),
                 YAML.dump("title" => "T", "github_review" => {"enabled" => true}, "chapters" => ["ch1.md"]))
      config = Ligarb::Config.new(File.join(dir, "book.yml"))
      assert config.github_review_enabled?
      assert_equal "book-feedback.yml", config.github_review_issue_template
      assert_equal ["feedback"], config.github_review_labels
    end
  end

  def test_config_accessors_disabled_when_absent
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "ch1.md"), "# C")
      File.write(File.join(dir, "book.yml"), YAML.dump("title" => "T", "chapters" => ["ch1.md"]))
      config = Ligarb::Config.new(File.join(dir, "book.yml"))
      refute config.github_review_enabled?
    end
  end
end
