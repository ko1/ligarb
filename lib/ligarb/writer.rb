# frozen_string_literal: true

require "yaml"
require "json"
require "fileutils"

module Ligarb
  class Writer
    class WriterError < RuntimeError; end

    BRIEF_FIELDS_FOR_BOOK_YML = %w[author output_dir chapter_numbers style repository].freeze

    def initialize(brief_path, no_build: false)
      @brief_path = File.expand_path(brief_path)
      @no_build = no_build
    end

    def run
      check_claude_installed!
      brief = load_brief
      output_dir = output_dir_for(brief)
      book_yml_path = File.join(output_dir, "book.yml")

      if File.exist?(book_yml_path)
        raise WriterError, "#{book_yml_path} already exists. Remove it first to regenerate."
      end

      FileUtils.mkdir_p(output_dir)
      prompt = build_prompt(brief, output_dir)
      run_claude(prompt)

      unless File.exist?(book_yml_path)
        raise WriterError, "Claude did not generate book.yml in #{output_dir}"
      end

      puts "Book files generated in #{output_dir}"

      unless @no_build
        puts "Building..."
        require_relative "builder"
        Builder.new(book_yml_path).build
      end

      book_yml_path
    end

    def self.init_brief(directory = nil)
      dir = directory || "."
      target = File.expand_path(dir)
      path = File.join(target, "brief.yml")

      if File.exist?(path)
        raise WriterError, "#{path} already exists."
      end

      FileUtils.mkdir_p(target)

      File.write(path, <<~YAML)
        # brief.yml - Book brief for ligarb write
        title: "My Book"
        language: ja
        audience: ""
        notes: |
          5章くらいで。
      YAML

      claude_md = File.join(target, "CLAUDE.md")
      created_claude_md = false
      unless File.exist?(claude_md)
        File.write(claude_md, <<~MD)
          # ligarb book project

          This is a book project using [ligarb](https://github.com/ko1/ligarb).

          ## Commands

          - `ligarb build` — Build the book (generates build/index.html)
          - `ligarb help` — Show full specification (Markdown syntax, config options, etc.)

          ## Key rules

          - All chapter files are Markdown (.md), listed in book.yml
          - The first h1 in each file is the chapter title
          - Use ```mermaid, ```math, admonitions (> [!NOTE]), etc. as needed
          - Run `ligarb build` after changes to verify the output
        MD
        created_claude_md = true
      end

      puts "Created #{path}"
      puts "Created #{claude_md}" if created_claude_md
      brief_arg = directory ? " #{path}" : ""
      puts "Edit brief.yml, then run 'ligarb write#{brief_arg}' to generate the book."
    end

    private

    def check_claude_installed!
      unless system("claude", "--version", out: File::NULL, err: File::NULL)
        raise WriterError, "'claude' command not found. Install Claude Code first."
      end
    end

    def load_brief
      unless File.exist?(@brief_path)
        raise WriterError, "#{@brief_path} not found."
      end

      brief = YAML.safe_load_file(@brief_path)
      unless brief.is_a?(Hash) && brief["title"] && !brief["title"].empty?
        raise WriterError, "'title' is required in #{@brief_path}."
      end

      brief
    end

    def output_dir_for(_brief)
      File.dirname(@brief_path)
    end

    def build_prompt(brief, output_dir)
      abs_output_dir = File.expand_path(output_dir)
      spec = CLI.spec_text

      lines = []
      lines << "You are writing a book using the ligarb tool."
      lines << ""
      lines << "<ligarb-spec>"
      lines << spec
      lines << "</ligarb-spec>"
      lines << ""
      lines << "Write a complete book based on this brief:"
      lines << "- Title: #{brief["title"]}"
      lines << "- Language: #{brief["language"] || "ja"}"
      lines << "- Target audience: #{brief["audience"]}" if brief["audience"] && !brief["audience"].empty?

      if brief["notes"] && !brief["notes"].strip.empty?
        lines << ""
        lines << "Additional instructions:"
        lines << brief["notes"].strip
      end

      book_yml_fields = BRIEF_FIELDS_FOR_BOOK_YML.select { |k| brief.key?(k) }
      if book_yml_fields.any?
        settings = book_yml_fields.map { |k| "#{k}: #{brief[k].inspect}" }.join(", ")
        lines << ""
        lines << "In book.yml, set: #{settings}"
      end

      lines << ""
      lines << "Create all files in: #{abs_output_dir}"
      lines << "In book.yml, always set: ai_generated: true"
      lines << "Create book.yml first, then each chapter .md file."
      lines << "Include a cover page for books with 4+ chapters."
      lines << "Each chapter: substantive content with multiple ## sections."
      lines << "Use code blocks, admonitions, mermaid diagrams where appropriate."
      lines << "Chapter filenames: 01-topic.md, 02-topic.md, etc."

      lines.join("\n")
    end

    def run_claude(prompt)
      tools = "Write,Bash,WebFetch,WebSearch"
      allowed = "Write,Bash(mkdir:*),Bash(ls:*),Bash(ligarb:*),WebFetch,WebSearch"
      cmd = ["claude", "-p", prompt, "--tools", tools, "--allowedTools", allowed,
             "--output-format", "stream-json", "--verbose"]
      puts "Writing with Claude... (this may take a few minutes)"
      unparsed_lines = []
      IO.popen(cmd, err: [:child, :out]) do |io|
        io.each_line do |line|
          unless parse_stream_event(line)
            unparsed_lines << line.rstrip
          end
        end
      end
      unless $?.success?
        msg = unparsed_lines.reject(&:empty?).last(10).join("\n")
        raise WriterError, "Claude process failed.#{"\n#{msg}" unless msg.empty?}"
      end
    end

    def parse_stream_event(line)
      json = JSON.parse(line) rescue (return false)
      case json["type"]
      when "content_block_start"
        tool = json.dig("content_block", "tool_use")
        if tool
          name = tool["name"]
          puts "  [#{name}]..." if name
        end
      end
      true
    end
  end
end
