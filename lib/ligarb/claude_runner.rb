# frozen_string_literal: true

require "json"
require "open3"
require_relative "cli"

module Ligarb
  class ClaudeRunner
    PATCH_RE = %r{<patch>\s*<<<\n(.*?)\n===\n(.*?)\n>>>\s*</patch>}m

    def initialize(config)
      @config = config
    end

    def installed?
      system("claude", "--version", out: File::NULL, err: File::NULL)
    end

    # Run claude -p with the given prompt. Returns the text response.
    def run(prompt)
      cmd = ["claude", "-p", prompt, "--model", "opus", "--output-format", "json"]
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

    # Build prompt for reviewing a comment on selected text.
    # Asks Claude to include <patch> blocks with concrete replacements.
    def review_prompt(review)
      ctx = review["context"]
      source_file = ctx["source_file"]
      source_content = File.exist?(source_file) ? File.read(source_file) : "(file not found)"

      messages = review["messages"].map { |m| "#{m["role"]}: #{m["content"]}" }.join("\n\n")

      sources_section = sources_prompt_section
      uploaded_section = uploaded_files_prompt_section(ctx)

      <<~PROMPT
        You are reviewing a chapter of a book built with ligarb.

        <ligarb-spec>
        #{CLI.spec_text}
        </ligarb-spec>
        #{sources_section}#{uploaded_section}
        Source file: #{source_file}

        Full chapter content:
        ```markdown
        #{source_content}
        ```

        The reader selected this text: "#{ctx["selected_text"]}"
        Under heading: #{ctx["heading_id"]}

        Conversation so far:
        #{messages}

        Respond to the reader's comment with a concise explanation, then provide
        concrete patches. Each patch must use this exact format:

        <patch>
        <<<
        exact text to find in the source (copied verbatim)
        ===
        replacement text
        >>>
        </patch>

        Rules:
        - The text between <<< and === must match the source file EXACTLY (whitespace included)
        - You may include multiple <patch> blocks if needed
        - Use ligarb Markdown features (admonitions, cross-references, index, etc.) where appropriate
        - If no code change is needed (e.g. answering a question), omit the <patch> blocks
      PROMPT
    end

    # Extract patches from the last assistant message and apply them.
    # No Claude call needed — pure string replacement + rebuild.
    def apply_patches(review)
      patches = extract_patches(review)
      return { "error" => "No patches found in the conversation" } if patches.empty?

      source_file = review.dig("context", "source_file")
      return { "error" => "Source file not found" } unless source_file && File.exist?(source_file)

      content = File.read(source_file)
      applied = 0

      patches.each do |old_text, new_text|
        if content.include?(old_text)
          content = content.sub(old_text, new_text)
          applied += 1
        end
      end

      return { "error" => "No patches matched the source file (0/#{patches.size})" } if applied == 0

      File.write(source_file, content)

      # Rebuild
      config_path = File.join(@config.base_dir, "book.yml")
      require_relative "builder"
      Builder.new(config_path).build

      { "text" => "Applied #{applied}/#{patches.size} patch(es) and rebuilt." }
    end

    def sources_prompt_section
      return "" if @config.sources.empty?

      lines = ["\nReference sources (read these files for context):"]
      @config.sources.each do |src|
        lines << "- #{src.label}: #{src.path}"
      end
      lines << ""
      lines.join("\n")
    end

    def uploaded_files_prompt_section(ctx)
      files = ctx["uploaded_files"]
      return "" unless files.is_a?(Array) && !files.empty?

      lines = ["\nUploaded reference files (read these for context):"]
      files.each do |f|
        lines << "- #{f["label"]}: #{f["path"]}"
      end
      lines << ""
      lines.join("\n")
    end

    # Parse <patch> blocks from assistant messages
    def extract_patches(review)
      (review["messages"] || [])
        .select { |m| m["role"] == "assistant" }
        .reverse
        .each do |msg|
          patches = msg["content"].scan(PATCH_RE)
          return patches unless patches.empty?
        end
      []
    end
  end
end
