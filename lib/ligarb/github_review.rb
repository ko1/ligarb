# frozen_string_literal: true

require "fileutils"
require "yaml"

module Ligarb
  # Sets up the GitHub-based review scaffolding (.github/ + SETUP.md) in a
  # project — the `ligarb setup-github-review` command. This is pure file
  # copying: ligarb never calls Claude or GitHub at runtime. The templates are
  # classified into layers so a future option could split them apart:
  #   - generic layer  : works without Claude (Pages deploy, build check, forms)
  #   - claude layer    : opt-in Claude integration (issue/PR handlers, SETUP.md)
  #
  # Re-running OVERWRITES the generated files so a project can follow upstream
  # template changes (e.g. after a ligarb upgrade). The user's own book.yml is
  # never overwritten. Since projects are git repos, `git diff` is the safety
  # net for reviewing/reverting changes after a re-sync.
  class GithubReview
    TEMPLATE_DIR = File.expand_path("../../templates/github_review", __dir__)

    # Generic layer: no Claude dependency.
    GENERIC_FILES = %w[
      .github/workflows/deploy-book.yml
      .github/workflows/build-check.yml
      .github/ISSUE_TEMPLATE/book-feedback.yml
      .github/ISSUE_TEMPLATE/config.yml
    ].freeze

    # Claude integration layer: opt-in.
    CLAUDE_FILES = %w[
      .github/workflows/claude-feedback.yml
      .github/workflows/claude-pr-mention.yml
      SETUP.md
      SETUP.sh
    ].freeze

    TEMPLATE_FILES = (GENERIC_FILES + CLAUDE_FILES).freeze

    Result = Struct.new(:created, :updated, :unchanged, keyword_init: true)

    # `ligarb setup-github-review [DIR]` entry point. Sets up the scaffolding in
    # an existing ligarb project (book.yml must exist), enables the reader
    # feedback UI in book.yml, and prints the remaining manual-setup steps.
    # Safe to re-run to pull in updated templates (generated files are
    # overwritten; book.yml is not).
    def self.run(directory = nil)
      target = File.expand_path(directory || ".")
      unless File.exist?(File.join(target, "book.yml"))
        $stderr.puts "Error: book.yml not found in #{target}"
        $stderr.puts "Run 'ligarb init' or 'ligarb write' first, then set up the GitHub review scaffolding."
        exit 1
      end

      reviewer = new(target)
      # book.yml edits must run BEFORE generate so the templates (SETUP.sh,
      # issue forms, README) are substituted with the resolved repository.
      repository = reviewer.ensure_repository_in_book_yml
      enabled = reviewer.enable_in_book_yml
      readme = reviewer.create_readme_if_absent
      result = reviewer.generate
      reviewer.print_notice(result, repository: repository, enabled: enabled, readme: readme)
    end

    def initialize(target)
      @target = File.expand_path(target)
    end

    # Writes all template files into the project, substituting __OWNER__ /
    # __REPO__ from book.yml's `repository:`. Existing files are OVERWRITTEN so a
    # project can follow upstream template changes; only files whose content is
    # already identical are left untouched. Returns a Result listing
    # created/updated/unchanged files.
    def generate
      owner, repo = extract_owner_repo
      created = []
      updated = []
      unchanged = []

      TEMPLATE_FILES.each do |rel|
        dest = File.join(@target, rel)
        content = render(rel, File.read(File.join(TEMPLATE_DIR, rel)), owner, repo)

        if !File.exist?(dest)
          write_file(dest, content)
          created << rel
        elsif File.read(dest) == content
          unchanged << rel
        else
          write_file(dest, content)
          updated << rel
        end
      end

      Result.new(created: created, updated: updated, unchanged: unchanged)
    end

    # Ensures `github_review.enabled: true` is present in book.yml so the reader
    # feedback UI activates (once `repository` is also set). Appends the key only
    # when absent, preserving existing formatting/comments. Returns :added,
    # :present, or :unsupported (translations hub / unparsable).
    def enable_in_book_yml
      book_yml = File.join(@target, "book.yml")
      data = YAML.safe_load_file(book_yml)
      return :unsupported unless data.is_a?(Hash)
      return :present if data.key?("github_review")

      content = File.read(book_yml).rstrip
      File.write(book_yml, "#{content}\n\ngithub_review:\n  enabled: true\n")
      :added
    end

    # Seeds a default `repository:` in book.yml when it has none, guessing
    # https://github.com/<os-user>/<dir-name>. This drives __OWNER__/__REPO__
    # substitution and the GH Pages link; the user edits it if the guess is
    # wrong. Returns :added, :present, or :unsupported. (@default_repository is
    # set to the guessed URL when :added, for the notice.)
    def ensure_repository_in_book_yml
      book_yml = File.join(@target, "book.yml")
      data = YAML.safe_load_file(book_yml)
      return :unsupported unless data.is_a?(Hash)
      return :present if data.key?("repository")

      user = ENV["USER"] || ENV["USERNAME"] || "your-github-account"
      @default_repository = "https://github.com/#{user}/#{File.basename(@target)}"
      content = File.read(book_yml).rstrip
      File.write(book_yml, %(#{content}\n\nrepository: "#{@default_repository}"\n))
      :added
    end

    # Creates a project README.md that links to the published GitHub Pages site,
    # but only when one does not already exist (the reader's own README is never
    # overwritten). Returns :created or :present.
    def create_readme_if_absent
      readme = File.join(@target, "README.md")
      return :present if File.exist?(readme)

      owner, repo = extract_owner_repo
      pages  = owner && repo ? "https://#{owner}.github.io/#{repo}/" : "https://__OWNER__.github.io/__REPO__/"
      issues = owner && repo ? "https://github.com/#{owner}/#{repo}/issues/new?template=book-feedback.yml" \
                             : "https://github.com/__OWNER__/__REPO__/issues/new?template=book-feedback.yml"
      title = book_title.to_s.empty? ? "Book" : book_title

      File.write(readme, <<~MD)
        # #{title}

        📖 **公開版（GitHub Pages）**: #{pages}

        この本は [ligarb](https://github.com/ko1/ligarb) で生成しています。

        ## フィードバック

        本文の誤り・わかりにくい点・疑問は [Issue](#{issues}) からどうぞ。
        公開ページでは本文を選択して「Report as issue」からも送れます。

        ## ローカルでビルド

        ```bash
        ligarb build   # build/index.html を生成
        ligarb serve   # ローカルプレビュー
        ```

        セットアップ手順は [SETUP.md](SETUP.md) を参照してください。
      MD
      :created
    end

    def print_notice(result, repository:, enabled:, readme:)
      puts "Set up GitHub review scaffolding in #{@target}:"
      result.created.each { |path| puts "  created    #{path}" }
      result.updated.each { |path| puts "  updated    #{path}" }
      puts "  created    README.md (with the GitHub Pages link)" if readme == :created
      case repository
      when :added then puts "  updated    book.yml (repository: #{@default_repository})"
      end
      case enabled
      when :added   then puts "  updated    book.yml (github_review.enabled: true)"
      when :present then puts "  kept       book.yml github_review setting"
      end
      unless result.unchanged.empty?
        puts "  unchanged  #{result.unchanged.size} file(s) already up to date"
      end
      if result.updated.any?
        puts
        puts "Note: existing scaffolding files were overwritten with the latest"
        puts "templates. Review with 'git diff' and revert any local edits you"
        puts "want to keep."
      end
      puts
      puts "Next: edit 'repository:' in book.yml if the guess is wrong, then run"
      puts "the gh CLI quickstart:"
      puts "  bash SETUP.sh    # repo create + secret + Pages + permissions + labels"
      puts
      puts "It still needs a token (see SETUP.md): generate one with"
      puts "'claude setup-token' before running SETUP.sh (it prompts for it)."
    end

    private

    def write_file(dest, content)
      FileUtils.mkdir_p(File.dirname(dest))
      File.write(dest, content)
      File.chmod(0o755, dest) if dest.end_with?(".sh")
    end

    def book_title
      data = YAML.safe_load_file(File.join(@target, "book.yml"))
      data.is_a?(Hash) ? data["title"] : nil
    rescue StandardError
      nil
    end

    # Substitute __OWNER__ / __REPO__ placeholders. When repository is unset we
    # leave the placeholders as-is, except config.yml's Discussions link which
    # we comment out so the issue chooser does not show a broken URL.
    def render(rel, content, owner, repo)
      if owner && repo
        content.gsub("__OWNER__", owner).gsub("__REPO__", repo)
      elsif rel == ".github/ISSUE_TEMPLATE/config.yml"
        comment_out_contact_links(content)
      else
        content
      end
    end

    def comment_out_contact_links(content)
      content.lines.map { |line|
        line.start_with?("contact_links:") || line.start_with?("  ") ? "# #{line}" : line
      }.join
    end

    # Reads book.yml's `repository:` and extracts [owner, repo].
    # Returns [nil, nil] when book.yml or repository is missing/unparsable.
    def extract_owner_repo
      book_yml = File.join(@target, "book.yml")
      return [nil, nil] unless File.exist?(book_yml)

      data = YAML.safe_load_file(book_yml)
      url = data.is_a?(Hash) ? data["repository"] : nil
      return [nil, nil] unless url.is_a?(String)

      m = url.chomp("/").match(%r{github\.com[/:]([^/]+)/([^/]+?)(?:\.git)?\z})
      m ? [m[1], m[2]] : [nil, nil]
    end
  end
end
