# frozen_string_literal: true

require "json"
require "open3"

module Ligarb
  class ClaudeRunner
    def initialize(config)
      @config = config
    end

    def installed?
      system("claude", "--version", out: File::NULL, err: File::NULL)
    end

    # Run claude -p with the given prompt. Returns the text response.
    # Runs synchronously (caller should use Thread for background execution).
    def run(prompt)
      cmd = ["claude", "-p", prompt, "--output-format", "json"]
      stdout, stderr, status = Open3.capture3(*cmd)

      unless status.success?
        return { "error" => "Claude process failed: #{stderr.strip}" }
      end

      begin
        result = JSON.parse(stdout)
        text = result["result"] || stdout
        { "text" => text }
      rescue JSON::ParserError
        { "text" => stdout.strip }
      end
    end

    # Build prompt for reviewing a comment on selected text
    def review_prompt(review)
      ctx = review["context"]
      source_file = ctx["source_file"]
      source_content = File.exist?(source_file) ? File.read(source_file) : "(file not found)"

      messages = review["messages"].map { |m| "#{m["role"]}: #{m["content"]}" }.join("\n\n")

      <<~PROMPT
        You are reviewing a chapter of a book written in Markdown.

        Source file: #{source_file}

        Full chapter content:
        ```markdown
        #{source_content}
        ```

        The reader selected this text: "#{ctx["selected_text"]}"
        Under heading: #{ctx["heading_id"]}

        Conversation so far:
        #{messages}

        Please respond to the reader's comment. Suggest specific improvements to the text if appropriate.
        Keep your response concise and actionable.
      PROMPT
    end

    # Build prompt for applying an approved change
    def apply_prompt(review)
      ctx = review["context"]
      source_file = ctx["source_file"]
      source_content = File.exist?(source_file) ? File.read(source_file) : "(file not found)"

      messages = review["messages"].map { |m| "#{m["role"]}: #{m["content"]}" }.join("\n\n")

      build_cmd = "ligarb build #{File.join(@config.base_dir, 'book.yml')}"

      <<~PROMPT
        Apply the approved changes to the Markdown source file.

        Source file: #{source_file}

        Current content:
        ```markdown
        #{source_content}
        ```

        Review conversation:
        #{messages}

        Instructions:
        1. Edit the file #{source_file} to apply the discussed changes
        2. After editing, run: #{build_cmd}
        3. Only modify what was discussed — do not make other changes
      PROMPT
    end

    def apply_changes(review)
      prompt = apply_prompt(review)
      source_file = review.dig("context", "source_file") || ""
      build_cmd = "ligarb build #{File.join(@config.base_dir, 'book.yml')}"

      cmd = [
        "claude", "-p", prompt,
        "--tools", "Edit,Bash",
        "--allowedTools", "Edit(#{source_file}),Bash(ligarb:*)",
        "--output-format", "json"
      ]

      stdout, stderr, status = Open3.capture3(*cmd)

      unless status.success?
        return { "error" => "Claude apply failed: #{stderr.strip}" }
      end

      begin
        result = JSON.parse(stdout)
        { "text" => result["result"] || stdout }
      rescue JSON::ParserError
        { "text" => stdout.strip }
      end
    end
  end
end
