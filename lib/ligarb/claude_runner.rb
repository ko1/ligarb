# frozen_string_literal: true

require "json"
require "open3"
require_relative "cli"

module Ligarb
  class ClaudeRunner
    PATCH_RE = %r{<patch(?:\s+file="([^"]*)")?>\s*<<<\n(.*?)\n===\n(.*?)\n>>>\s*</patch>}m

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
    # Includes all chapter contents so Claude can produce cross-chapter patches.
    def review_prompt(review)
      ctx = review["context"]
      source_file = ctx["source_file"]

      messages = review["messages"].map { |m| "#{m["role"]}: #{m["content"]}" }.join("\n\n")

      sources_section = sources_prompt_section
      uploaded_section = uploaded_files_prompt_section(ctx)

      all_chapters = all_chapters_section(source_file)
      bib_section = bibliography_section

      <<~PROMPT
        You are reviewing a book built with ligarb.

        <ligarb-spec>
        #{CLI.spec_text}
        </ligarb-spec>
        #{sources_section}#{uploaded_section}
        The comment was made on: #{relative_path(source_file)}
        #{all_chapters}#{bib_section}
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
        - The file attribute must be the relative path shown in the chapter/bibliography headings above
        - The text between <<< and === must match the source file EXACTLY (whitespace included)
        - You may include multiple <patch> blocks for one or more files
        - If the comment applies to multiple chapters, provide patches for ALL relevant chapters
        - When adding citations ([@key]), also add the corresponding entry to the bibliography file
        - Use ligarb Markdown features (admonitions, cross-references, index, etc.) where appropriate
        - If no code change is needed (e.g. answering a question), omit the <patch> blocks
      PROMPT
    end

    # Extract patches from the last assistant message and apply them.
    # Supports cross-chapter patches via the file attribute.
    def apply_patches(review)
      patches = extract_patches(review)
      return { "error" => "No patches found in the conversation" } if patches.empty?

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

    private

    # Build a section showing all chapter contents for cross-chapter context.
    def all_chapters_section(commented_file)
      lines = ["\nAll chapters in this book:"]
      @config.all_file_paths.each do |path|
        rel = relative_path(path)
        marker = path == commented_file ? " (commented chapter)" : ""
        content = File.exist?(path) ? File.read(path) : "(file not found)"
        lines << "\n### #{rel}#{marker}"
        lines << "```markdown"
        lines << content
        lines << "```"
      end
      lines.join("\n")
    end

    # Build a section showing the bibliography file contents.
    def bibliography_section
      bib_path = @config.bibliography_path
      return "" unless bib_path && File.exist?(bib_path)

      rel = relative_path(bib_path)
      content = File.read(bib_path)
      <<~SECTION

        Bibliography file:

        ### #{rel}
        ```
        #{content}
        ```
      SECTION
    end

    # Convert absolute path to relative path from base_dir.
    def relative_path(path)
      return path unless path

      base = @config.base_dir + "/"
      path.start_with?(base) ? path.delete_prefix(base) : path
    end

    # Resolve a relative path from a patch to an absolute path.
    def resolve_patch_file(rel_path)
      absolute = File.join(@config.base_dir, rel_path)
      return absolute if File.exist?(absolute)

      # Try matching by basename against all chapter paths
      @config.all_file_paths.find { |p| p.end_with?("/#{rel_path}") || p == rel_path }
    end
  end
end
