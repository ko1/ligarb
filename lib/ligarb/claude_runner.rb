# frozen_string_literal: true

require "json"
require "open3"
require_relative "cli"

module Ligarb
  class ClaudeRunner
    PATCH_RE = %r{<patch(?:\s+file="([^"]*)")?>\s*<<<[ \t]*\r?\n(.*?)\r?\n===[ \t]*\r?\n(.*?)\r?\n>>>[ \t]*\s*</patch>}m

    def initialize(config)
      @config = config
    end

    def installed?
      claude_path = which("claude")
      return :not_found unless claude_path

      if system(claude_path, "--version", out: File::NULL, err: File::NULL)
        true
      else
        :version_failed
      end
    end

    # Run claude -p with the given prompt. Returns the text response.
    def run(prompt)
      cmd = ["claude", "-p", "-", "--model", "opus", "--output-format", "json"]
      stdout, stderr, status = Open3.capture3(*cmd, stdin_data: prompt)

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
    # Points Claude to book.yml so it can read chapters and bibliography as needed.
    def review_prompt(review)
      ctx = review["context"]
      source_file = ctx["source_file"]
      config_path = File.join(@config.base_dir, "book.yml")

      messages = review["messages"].map { |m| "#{m["role"]}: #{m["content"]}" }.join("\n\n")

      uploaded_section = uploaded_files_prompt_section(ctx)

      <<~PROMPT
        You are reviewing a book built with ligarb.

        <ligarb-spec>
        #{CLI.spec_text}
        </ligarb-spec>
        #{uploaded_section}
        Book configuration: #{config_path}
        Read this file first to understand the book structure (chapters, bibliography, sources, etc.).
        Then read the chapter files and other files as needed to respond to the comment.

        The comment was made on: #{source_file}
        The reader selected this text: "#{ctx["selected_text"]}"
        Under heading: #{ctx["heading_id"]}

        Conversation so far:
        #{messages}

        Respond to the reader's comment with a concise explanation, then provide
        concrete patches. Each patch must use this exact format:

        <patch file="relative/path/to/file.md">
        <<<
        exact text to find in the source (copied verbatim)
        ===
        replacement text
        >>>
        </patch>

        Rules:
        - The file attribute must be the path relative to the directory containing book.yml
        - The text between <<< and === must match the source file EXACTLY (whitespace included)
        - You may include multiple <patch> blocks for one or more files
        - If the comment applies to multiple chapters, read all relevant chapters and provide patches for each
        - When adding citations ([@key]), also add the corresponding entry to the bibliography file
        - Use ligarb Markdown features (admonitions, cross-references, index, etc.) where appropriate
        - If no code change is needed (e.g. answering a question), omit the <patch> blocks
      PROMPT
    end

    # Extract patches from the last assistant message and apply them.
    # Supports cross-chapter patches via the file attribute.
    def apply_patches(review)
      patches = extract_patches(review)
      if patches.empty?
        hint = has_unmatched_patches?(review) ? " (patch tags found but format didn't match)" : ""
        return { "error" => "No patches found in the conversation#{hint}" }
      end

      default_source = review.dig("context", "source_file")

      # Group patches by target file
      file_patches = {}
      patches.each do |rel_path, old_text, new_text|
        target = if rel_path && !rel_path.empty?
                   resolve_patch_file(rel_path)
                 else
                   default_source
                 end
        next unless target

        file_patches[target] ||= []
        file_patches[target] << [old_text, new_text]
      end

      return { "error" => "No valid target files found for patches" } if file_patches.empty?

      applied = 0
      total = patches.size

      file_patches.each do |file, file_patch_list|
        unless File.exist?(file)
          next
        end

        content = File.read(file)
        changed = false

        file_patch_list.each do |old_text, new_text|
          if content.include?(old_text)
            content = content.sub(old_text, new_text)
            applied += 1
            changed = true
          end
        end

        File.write(file, content) if changed
      end

      return { "error" => "No patches matched the source files (0/#{total})" } if applied == 0

      # Rebuild
      config_path = File.join(@config.base_dir, "book.yml")
      require_relative "builder"
      begin
        Builder.new(config_path).build
      rescue SystemExit => e
        return { "error" => "Applied #{applied}/#{total} patch(es) but rebuild failed: #{e.message}" }
      end

      { "text" => "Applied #{applied}/#{total} patch(es) and rebuilt." }
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

    # Parse <patch> blocks from assistant messages.
    # Returns array of [file_path_or_nil, old_text, new_text].
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

    # Check if assistant messages contain <patch> tags that didn't match PATCH_RE.
    def has_unmatched_patches?(review)
      (review["messages"] || [])
        .select { |m| m["role"] == "assistant" }
        .any? { |m| m["content"].include?("<patch") && m["content"].include?("</patch>") }
    end

    private

    def which(cmd)
      ENV["PATH"].to_s.split(File::PATH_SEPARATOR).each do |dir|
        path = File.join(dir, cmd)
        return path if File.executable?(path)
      end
      nil
    end

    # Resolve a relative path from a patch to an absolute path.
    # Prevents path traversal outside base_dir.
    def resolve_patch_file(rel_path)
      absolute = File.expand_path(rel_path, @config.base_dir)
      base_dir = File.expand_path(@config.base_dir)

      # Reject paths that escape base_dir (e.g. "../../etc/passwd")
      unless absolute.start_with?(base_dir + "/")
        $stderr.puts "Warning: patch path '#{rel_path}' resolves outside project directory, skipping"
        return nil
      end

      return absolute if File.exist?(absolute)

      # Try matching by basename against all chapter paths
      @config.all_file_paths.find { |p| p.end_with?("/#{rel_path}") || p == rel_path }
    end
  end
end
