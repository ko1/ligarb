# frozen_string_literal: true

require_relative "test_helper"
require "ligarb/mermaid_checker"

class MermaidCheckerTest < Minitest::Test
  # The harness needs Node and a real mermaid.min.js. Locate a provisioned
  # copy from a prior build; skip the integration tests if either is missing.
  MERMAID_JS = Dir.glob(File.expand_path("../**/build/**/js/mermaid.min.js", __dir__)).first

  def node_available?
    system("node", "--version", out: File::NULL, err: File::NULL)
  end

  def make_chapter(content)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "01-test.md")
      File.write(path, content)
      yield Ligarb::Chapter.new(path, dir)
    end
  end

  def test_no_blocks_returns_zero_without_running
    make_chapter("# Title\n\nNo diagrams.") do |ch|
      # Even with a bogus path, no blocks means no work and no error.
      assert_equal 0, Ligarb::MermaidChecker.check([ch], "/nonexistent/mermaid.min.js")
    end
  end

  def test_missing_mermaid_js_is_skipped_with_warning
    make_chapter("```mermaid\ngraph TD\n  A-->B\n```") do |ch|
      out, err = capture_subprocess_io do
        assert_equal 0, Ligarb::MermaidChecker.check([ch], "/nonexistent/mermaid.min.js")
      end
      assert_empty out
      assert_match(/not found.*skipping mermaid syntax check/, err)
    end
  end

  def test_valid_diagram_passes
    skip "node not available" unless node_available?
    skip "mermaid.min.js not available" unless MERMAID_JS
    make_chapter("```mermaid\ngraph LR\n  A[Start] --> B{OK?}\n```") do |ch|
      capture_subprocess_io do
        assert_equal 0, Ligarb::MermaidChecker.check([ch], MERMAID_JS)
      end
    end
  end

  def test_invalid_diagram_warns_with_location
    skip "node not available" unless node_available?
    skip "mermaid.min.js not available" unless MERMAID_JS
    make_chapter("# Title\n\n```mermaid\ngraph TD\n  A -=-> B ???\n```") do |ch|
      _out, err = capture_subprocess_io do
        assert_equal 1, Ligarb::MermaidChecker.check([ch], MERMAID_JS)
      end
      assert_match(/mermaid syntax error in .*01-test\.md:4/, err)
      assert_match(/Parse error/, err)
    end
  end

  # Regression: a <br> in a node label is valid mermaid, but the Node DOM stub
  # cannot run DOMPurify over HTML, which used to surface as a false-positive
  # "syntax error" warning. Such environment errors must be suppressed.
  def test_html_label_is_not_a_false_positive
    skip "node not available" unless node_available?
    skip "mermaid.min.js not available" unless MERMAID_JS
    make_chapter("```mermaid\ngraph LR\n  A[1行目<br>2行目] --> B[OK]\n```") do |ch|
      _out, err = capture_subprocess_io do
        assert_equal 0, Ligarb::MermaidChecker.check([ch], MERMAID_JS)
      end
      refute_match(/mermaid syntax error/, err)
    end
  end
end
