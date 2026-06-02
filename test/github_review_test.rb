# frozen_string_literal: true

require_relative "test_helper"
require "ligarb/github_review"
require "ligarb/initializer"

class GithubReviewTest < Minitest::Test
  # Files written by GithubReview#generate (overwrite-managed). README.md is
  # handled separately (create-if-absent), so it is intentionally not here.
  EXPECTED_FILES = %w[
    .github/workflows/deploy-book.yml
    .github/workflows/build-check.yml
    .github/workflows/claude-feedback.yml
    .github/workflows/claude-pr-mention.yml
    .github/ISSUE_TEMPLATE/book-feedback.yml
    .github/ISSUE_TEMPLATE/config.yml
    SETUP.md
    SETUP.sh
  ].freeze

  def with_project(book_data: {"title" => "T", "chapters" => ["a.md"]})
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "book.yml"), YAML.dump(book_data)) if book_data
      yield dir
    end
  end

  def test_generates_all_template_files
    with_project do |dir|
      result = Ligarb::GithubReview.new(dir).generate
      EXPECTED_FILES.each do |rel|
        assert File.exist?(File.join(dir, rel)), "expected #{rel} to be generated"
      end
      assert_equal EXPECTED_FILES.sort, result.created.sort
      assert_empty result.updated
      assert_empty result.unchanged
    end
  end

  def test_setup_sh_is_executable
    with_project do |dir|
      Ligarb::GithubReview.new(dir).generate
      assert File.executable?(File.join(dir, "SETUP.sh")), "SETUP.sh should be executable"
    end
  end

  def test_setup_sh_substitutes_owner_and_repo
    book = {"title" => "T", "chapters" => ["a.md"],
            "repository" => "https://github.com/alice/mybook"}
    with_project(book_data: book) do |dir|
      Ligarb::GithubReview.new(dir).generate
      sh = File.read(File.join(dir, "SETUP.sh"))
      assert_includes sh, 'OWNER="alice"'
      assert_includes sh, 'REPO="mybook"'
      refute_includes sh, "__OWNER__"
    end
  end

  def test_substitutes_owner_and_repo
    book = {"title" => "T", "chapters" => ["a.md"],
            "repository" => "https://github.com/alice/mybook"}
    with_project(book_data: book) do |dir|
      Ligarb::GithubReview.new(dir).generate

      form = File.read(File.join(dir, ".github/ISSUE_TEMPLATE/book-feedback.yml"))
      assert_includes form, "https://alice.github.io/mybook/"
      refute_includes form, "__OWNER__"
      refute_includes form, "__REPO__"

      config = File.read(File.join(dir, ".github/ISSUE_TEMPLATE/config.yml"))
      assert_includes config, "https://github.com/alice/mybook/discussions"
    end
  end

  def test_substitutes_with_trailing_slash_and_git_suffix
    book = {"title" => "T", "chapters" => ["a.md"],
            "repository" => "https://github.com/alice/mybook.git"}
    with_project(book_data: book) do |dir|
      Ligarb::GithubReview.new(dir).generate
      config = File.read(File.join(dir, ".github/ISSUE_TEMPLATE/config.yml"))
      assert_includes config, "https://github.com/alice/mybook/discussions"
    end
  end

  def test_fallback_when_repository_unset
    with_project do |dir|
      Ligarb::GithubReview.new(dir).generate

      # Placeholders are left as-is in non-config files.
      form = File.read(File.join(dir, ".github/ISSUE_TEMPLATE/book-feedback.yml"))
      assert_includes form, "__OWNER__"

      # The Discussions link is commented out so the chooser shows no broken URL.
      config = File.read(File.join(dir, ".github/ISSUE_TEMPLATE/config.yml"))
      assert_includes config, "blank_issues_enabled: false"
      refute_match(/^contact_links:/, config)
      refute_match(%r{^  - name:}, config)
      assert_includes config, "# contact_links:"
    end
  end

  def test_overwrites_existing_files_to_follow_upstream
    with_project do |dir|
      target = File.join(dir, "SETUP.md")
      FileUtils.mkdir_p(File.dirname(target))
      File.write(target, "STALE LOCAL COPY")

      result = Ligarb::GithubReview.new(dir).generate

      # The stale file is replaced with the current template and reported.
      refute_equal "STALE LOCAL COPY", File.read(target)
      assert_includes result.updated, "SETUP.md"
      refute_includes result.created, "SETUP.md"
    end
  end

  def test_unchanged_files_are_not_rewritten
    with_project do |dir|
      gr = Ligarb::GithubReview.new(dir)
      gr.generate
      result = gr.generate # second identical run

      assert_empty result.created
      assert_empty result.updated
      assert_equal EXPECTED_FILES.sort, result.unchanged.sort
    end
  end

  def test_generated_yaml_is_parseable
    with_project(book_data: {"title" => "T", "chapters" => ["a.md"],
                             "repository" => "https://github.com/alice/mybook"}) do |dir|
      Ligarb::GithubReview.new(dir).generate
      Dir.glob(File.join(dir, ".github/**/*.yml")).each do |path|
        assert YAML.safe_load_file(path), "#{path} should parse as YAML"
      end
    end
  end

  def test_issue_form_has_no_type_dropdown
    with_project do |dir|
      Ligarb::GithubReview.new(dir).generate
      form = File.read(File.join(dir, ".github/ISSUE_TEMPLATE/book-feedback.yml"))
      # Readers no longer classify the feedback; Claude decides.
      refute_includes form, "id: type"
      refute_includes form, "type: dropdown"
      assert_includes form, "id: details"
    end
  end

  def test_feedback_workflow_handles_issue_comments
    with_project do |dir|
      Ligarb::GithubReview.new(dir).generate
      wf = File.read(File.join(dir, ".github/workflows/claude-feedback.yml"))
      # Follow-up conversation on issues must be picked up, not just opened/labeled.
      assert_includes wf, "issue_comment"
      # The prompt reads the whole thread (comments), not just title/body/labels.
      assert_includes wf, "title,body,labels,comments"
    end
  end

  def test_does_not_expand_github_actions_expressions
    with_project(book_data: {"title" => "T", "chapters" => ["a.md"],
                             "repository" => "https://github.com/alice/mybook"}) do |dir|
      Ligarb::GithubReview.new(dir).generate
      deploy = File.read(File.join(dir, ".github/workflows/deploy-book.yml"))
      # The ${{ ... }} Actions expression must survive verbatim.
      assert_includes deploy, "${{ steps.deployment.outputs.page_url }}"
    end
  end

  # --- enable_in_book_yml ---

  def test_enable_in_book_yml_appends_when_absent
    with_project do |dir|
      assert_equal :added, Ligarb::GithubReview.new(dir).enable_in_book_yml
      data = YAML.safe_load_file(File.join(dir, "book.yml"))
      assert_equal true, data.dig("github_review", "enabled")
      # Existing keys are preserved.
      assert_equal "T", data["title"]
    end
  end

  def test_enable_in_book_yml_idempotent_when_present
    book = {"title" => "T", "chapters" => ["a.md"], "github_review" => {"enabled" => false}}
    with_project(book_data: book) do |dir|
      assert_equal :present, Ligarb::GithubReview.new(dir).enable_in_book_yml
      # Must not flip the existing value.
      data = YAML.safe_load_file(File.join(dir, "book.yml"))
      assert_equal false, data.dig("github_review", "enabled")
    end
  end

  # --- ensure_repository_in_book_yml ---

  def test_ensure_repository_seeds_default_when_absent
    with_project do |dir|
      assert_equal :added, Ligarb::GithubReview.new(dir).ensure_repository_in_book_yml
      data = YAML.safe_load_file(File.join(dir, "book.yml"))
      assert_match(%r{\Ahttps://github\.com/[^/]+/#{Regexp.escape(File.basename(dir))}\z}, data["repository"])
    end
  end

  def test_ensure_repository_kept_when_present
    book = {"title" => "T", "chapters" => ["a.md"], "repository" => "https://github.com/me/mine"}
    with_project(book_data: book) do |dir|
      assert_equal :present, Ligarb::GithubReview.new(dir).ensure_repository_in_book_yml
      content = File.read(File.join(dir, "book.yml"))
      assert_equal 1, content.scan(/^repository:/).size
      assert_equal "https://github.com/me/mine", YAML.safe_load_file(File.join(dir, "book.yml"))["repository"]
    end
  end

  # --- create_readme_if_absent ---

  def test_creates_readme_with_pages_link
    book = {"title" => "My Great Book", "chapters" => ["a.md"],
            "repository" => "https://github.com/alice/mybook"}
    with_project(book_data: book) do |dir|
      assert_equal :created, Ligarb::GithubReview.new(dir).create_readme_if_absent
      readme = File.read(File.join(dir, "README.md"))
      assert_includes readme, "My Great Book"
      assert_includes readme, "https://alice.github.io/mybook/"
    end
  end

  def test_does_not_overwrite_existing_readme
    with_project do |dir|
      File.write(File.join(dir, "README.md"), "MY OWN README")
      assert_equal :present, Ligarb::GithubReview.new(dir).create_readme_if_absent
      assert_equal "MY OWN README", File.read(File.join(dir, "README.md"))
    end
  end

  # --- setup-github-review command (GithubReview.run) ---

  def test_run_command_generates_scaffolding_and_enables
    with_project do |dir|
      capture_io { Ligarb::GithubReview.run(dir) }
      EXPECTED_FILES.each do |rel|
        assert File.exist?(File.join(dir, rel)), "expected #{rel}"
      end
      data = YAML.safe_load_file(File.join(dir, "book.yml"))
      assert_equal true, data.dig("github_review", "enabled")
    end
  end

  def test_run_command_errors_without_book_yml
    Dir.mktmpdir do |dir|
      out, err = capture_io do
        assert_raises(SystemExit) { Ligarb::GithubReview.run(dir) }
      end
      assert_match(/book\.yml not found/, err)
      refute File.exist?(File.join(dir, ".github")), ".github must not be generated"
    end
  end

  def test_run_command_is_idempotent
    with_project do |dir|
      capture_io { Ligarb::GithubReview.run(dir) }
      # Second run: nothing changes, no error, github_review key not duplicated.
      out, = capture_io { Ligarb::GithubReview.run(dir) }
      assert_match(/up to date/, out)
      content = File.read(File.join(dir, "book.yml"))
      assert_equal 1, content.scan(/^github_review:/).size
    end
  end

  def test_run_command_resyncs_modified_file
    with_project do |dir|
      capture_io { Ligarb::GithubReview.run(dir) }
      workflow = File.join(dir, ".github/workflows/build-check.yml")
      File.write(workflow, "# locally edited\n")

      out, = capture_io { Ligarb::GithubReview.run(dir) }

      # The edited file is restored to the current template and reported updated.
      assert_includes File.read(workflow), "ligarb build"
      assert_match(%r{updated\s+\.github/workflows/build-check\.yml}, out)
    end
  end

  # --- plain init must remain free of scaffolding ---

  def test_init_generates_no_scaffolding
    Dir.mktmpdir do |parent|
      target = File.join(parent, "demo")
      capture_io { Ligarb::Initializer.new(target).run }
      refute File.exist?(File.join(target, ".github")), ".github must not be generated"
      refute File.exist?(File.join(target, "SETUP.md")), "SETUP.md must not be generated"
      refute_includes File.read(File.join(target, "book.yml")), "github_review"
    end
  end
end
