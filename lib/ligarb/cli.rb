# frozen_string_literal: true

require_relative "version"
require_relative "builder"
require_relative "initializer"

module Ligarb
  module CLI
    module_function

    def run(args)
      command = args.shift

      case command
      when "build"
        config_path = args.first || "book.yml"
        Builder.new(config_path).build
      when "init"
        Initializer.new(args.first).run
      when "setup-github-review"
        require_relative "github_review"
        owner_idx = args.index("--owner") || args.index("--user")
        owner = owner_idx ? args[owner_idx + 1] : nil
        abort "Error: --owner requires a value (e.g. --owner my-org)" if owner_idx && (owner.nil? || owner.start_with?("--"))
        positional = args.each_index.reject { |i| args[i].start_with?("--") || i == owner_idx&.+(1) }
        directory = positional.map { |i| args[i] }.first
        GithubReview.run(directory, owner: owner)
      when "serve"
        port, port_idx = parse_port(args)
        host, host_idx = parse_host(args)
        # Drop flags and the --port/--host values so they aren't mistaken for CONFIG paths.
        value_indices = [port_idx, host_idx].compact.map { |i| i + 1 }
        config_paths = args.each_index
                           .reject { |i| args[i].start_with?("--") || value_indices.include?(i) }
                           .map { |i| args[i] }
        config_paths = ["book.yml"] if config_paths.empty?
        multi = args.include?("--multi")
        require_relative "server"
        Server.new(config_paths, port: port, host: host, multi: multi).start
      when "librarium"
        config_paths = Dir.glob("*/book.yml").sort
        abort "Error: no */book.yml found in current directory" if config_paths.empty?
        port, = parse_port(args)
        host, = parse_host(args)
        require_relative "server"
        Server.new(config_paths, port: port, host: host, multi: true).start
      when "write"
        require_relative "writer"
        begin
          if args.delete("--init")
            Writer.init_brief(args.first)
          else
            brief_path = args.reject { |a| a.start_with?("--") }.first || "brief.yml"
            no_build = args.include?("--no-build")
            Writer.new(brief_path, no_build: no_build).run
          end
        rescue Writer::WriterError => e
          $stderr.puts "Error: #{e.message}"
          exit 1
        end
      when "--help", "-h", nil
        print_usage
      when "help"
        print_spec
      when "version", "--version", "-v"
        puts "ligarb #{VERSION}"
      else
        $stderr.puts "Unknown command: #{command}"
        $stderr.puts "Run 'ligarb --help' for usage information."
        exit 1
      end
    end

    # Parses `--port N` from args. Returns [port, flag_index]; port defaults to
    # 3000 when --port is absent (flag_index is then nil). Aborts on a missing
    # or out-of-range value.
    def parse_port(args)
      idx = args.index("--port")
      return [3000, nil] unless idx

      value = args[idx + 1]
      abort "Error: --port requires a value (e.g. --port 8080)" if value.nil? || value.start_with?("--")
      port = value.to_i
      abort "Error: port must be 1-65535" unless (1..65535).include?(port)
      [port, idx]
    end

    # Parses `--host ADDR` from args. Returns [host, flag_index]; host defaults
    # to "127.0.0.1" (loopback only) when --host is absent (flag_index is then
    # nil). Aborts on a missing value.
    def parse_host(args)
      idx = args.index("--host")
      return ["127.0.0.1", nil] unless idx

      value = args[idx + 1]
      abort "Error: --host requires a value (e.g. --host 0.0.0.0)" if value.nil? || value.start_with?("--")
      [value, idx]
    end

    def print_usage
      puts <<~USAGE
        ligarb #{VERSION} - Generate a single-page HTML book from Markdown files

        Usage:
          ligarb init [DIRECTORY]  Create a new book project
          ligarb setup-github-review [DIRECTORY] [--owner NAME]
                                  Set up (or update) GitHub Pages + review workflows
                                  (--owner/--user seeds repository: owner when unset)
          ligarb build [CONFIG]    Build the HTML book (default CONFIG: book.yml)
          ligarb serve [CONFIG] [--port N] [--host ADDR]
                                  Serve the book with live reload and review UI
                                  (--host ADDR binds the interface; default
                                  127.0.0.1. Use 0.0.0.0 to expose on the LAN)
          ligarb librarium [--port N] [--host ADDR]
                                  Serve all */book.yml as a multi-book library
          ligarb write [BRIEF]         Generate a book with AI from brief.yml
          ligarb write --init [DIR]    Create DIR/brief.yml template
          ligarb help              Show detailed specification (for AI integration)
          ligarb version          Show version number

        Options:
          -h, --help              Show this usage summary
          -v, --version           Show version number

        Configuration (book.yml):
          title            (required) Book title
          chapters         (required) Book structure (chapters, parts, appendix)
          author           (optional) Author name (default: "")
          language         (optional) HTML lang attribute (default: "en")
          output_dir       (optional) Output directory (default: "build")
          chapter_numbers  (optional) Show chapter/section numbers (default: true)
          style            (optional) Custom CSS file path (default: none)
          repository       (optional) GitHub repository URL for "Edit on GitHub" links
          ai_generated     (optional) Mark as AI-generated (badge + meta tags, default: false)
          footer           (optional) Custom text at bottom of each chapter
          github_review    (optional) Enable the "Report as issue" reader feedback UI ({enabled: true}, needs repository)
          translations     (optional) Map of lang => config path for multi-language builds

        Example:
          ligarb build
          ligarb build path/to/book.yml
      USAGE
    end

    HELP_PATH = File.expand_path("../../../docs/help.md", __FILE__)

    def spec_text
      "ligarb #{VERSION}\n\n#{File.read(HELP_PATH)}"
    end

    def print_spec
      puts spec_text
    end
  end
end
