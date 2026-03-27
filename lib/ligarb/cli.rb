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
      when "serve"
        config_paths = args.reject { |a| a.start_with?("--") }
        config_paths = ["book.yml"] if config_paths.empty?
        port_idx = args.index("--port")
        port = port_idx ? args[port_idx + 1].to_i : 3000
        abort "Error: port must be 1-65535" unless (1..65535).include?(port)
        multi = args.include?("--multi")
        require_relative "server"
        Server.new(config_paths, port: port, multi: multi).start
      when "librarium"
        config_paths = Dir.glob("*/book.yml").sort
        abort "Error: no */book.yml found in current directory" if config_paths.empty?
        port_idx = args.index("--port")
        port = port_idx ? args[port_idx + 1].to_i : 3000
        abort "Error: port must be 1-65535" unless (1..65535).include?(port)
        require_relative "server"
        Server.new(config_paths, port: port, multi: true).start
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

    def print_usage
      puts <<~USAGE
        ligarb #{VERSION} - Generate a single-page HTML book from Markdown files

        Usage:
          ligarb init [DIRECTORY]  Create a new book project
          ligarb build [CONFIG]    Build the HTML book (default CONFIG: book.yml)
          ligarb serve [CONFIG]   Serve the book with live reload and review UI
          ligarb librarium       Serve all */book.yml as a multi-book library
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
          translations     (optional) Map of lang => config path for multi-language builds

        Example:
          ligarb build
          ligarb build path/to/book.yml
      USAGE
    end

    HELP_PATH = File.expand_path("../../../docs/help.md", __FILE__)

    def spec_text
      File.read(HELP_PATH).gsub("{{VERSION}}", VERSION)
    end

    def print_spec
      puts spec_text
    end
  end
end
