# frozen_string_literal: true

require "yaml"
require "fileutils"

module Ligarb
  class Writer
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
        $stderr.puts "Error: #{book_yml_path} already exists. Remove it first to regenerate."
        exit 1
      end

      FileUtils.mkdir_p(output_dir)
      prompt = build_prompt(brief, output_dir)
      run_claude(prompt)

      unless File.exist?(book_yml_path)
        $stderr.puts "Error: Claude did not generate book.yml in #{output_dir}"
        exit 1
      end

      puts "Book files generated in #{output_dir}"

      unless @no_build
        puts "Building..."
        require_relative "builder"
        Builder.new(book_yml_path).build
      end
    end

    def self.init_brief(directory = nil)
      dir = directory || "."
      target = File.expand_path(dir)
      path = File.join(target, "brief.yml")

      if File.exist?(path)
        $stderr.puts "Error: #{path} already exists."
        exit 1
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

      puts "Created #{path}"
      puts "Edit it, then run 'ligarb write #{path}' to generate the book." if directory
      puts "Edit it, then run 'ligarb write' to generate the book." unless directory
    end

    private

    def check_claude_installed!
      unless system("claude", "--version", out: File::NULL, err: File::NULL)
        $stderr.puts "Error: 'claude' command not found. Install Claude Code first."
        exit 1
      end
    end

    def load_brief
      unless File.exist?(@brief_path)
        $stderr.puts "Error: #{@brief_path} not found."
        exit 1
      end

      brief = YAML.safe_load_file(@brief_path)
      unless brief.is_a?(Hash) && brief["title"] && !brief["title"].empty?
        $stderr.puts "Error: 'title' is required in #{@brief_path}."
        exit 1
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
      cmd = ["claude", "-p", "--verbose", prompt, "--tools", tools, "--allowedTools", allowed]
      unless system(*cmd)
        $stderr.puts "Error: Claude process failed."
        exit 1
      end
    end
  end
end
