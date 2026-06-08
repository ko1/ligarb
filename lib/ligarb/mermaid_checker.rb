# frozen_string_literal: true

require "json"
require "open3"

module Ligarb
  # Build-time syntax check for mermaid blocks. Runs the downloaded
  # mermaid.min.js under Node (assets/mermaid_check.mjs) and calls
  # mermaid.parse() on each block. Reports syntax errors as warnings with
  # file:line locations; never fails the build (the generated HTML already
  # shows an error box for broken diagrams at view time).
  class MermaidChecker
    HARNESS = File.expand_path("../../assets/mermaid_check.mjs", __dir__)

    # chapters: Chapter objects (mermaid_blocks may be empty)
    # mermaid_js: path to the provisioned mermaid.min.js
    # Returns the number of blocks with syntax errors.
    def self.check(chapters, mermaid_js)
      new(chapters, mermaid_js).check
    end

    def initialize(chapters, mermaid_js)
      @chapters = chapters
      @mermaid_js = mermaid_js
    end

    def check
      blocks = collect_blocks
      return 0 if blocks.empty?

      unless File.exist?(@mermaid_js)
        warn "Warning: #{@mermaid_js} not found; skipping mermaid syntax check"
        return 0
      end

      results = run_harness(blocks)
      return 0 unless results

      error_count = 0
      results.each do |result|
        error = result["error"]
        next unless error

        error_count += 1
        block = blocks[result["id"]]
        warn "Warning: mermaid syntax error in #{block[:location]}"
        error.each_line { |l| warn "  #{l.chomp}" }
      end
      error_count
    end

    private

    def collect_blocks
      blocks = []
      @chapters.each do |ch|
        ch.mermaid_blocks.each do |block|
          location = block.line ? "#{ch.path}:#{block.line}" : ch.path
          blocks << { id: blocks.size, text: block.text, location: location }
        end
      end
      blocks
    end

    def run_harness(blocks)
      input = JSON.generate(blocks.map { |b| { id: b[:id], text: b[:text] } })
      stdout, stderr, status = Open3.capture3("node", HARNESS, @mermaid_js, stdin_data: input)
      unless status.success?
        warn "Warning: mermaid syntax check failed to run (node exited #{status.exitstatus}); skipping"
        stderr.each_line.first(3).each { |l| warn "  #{l.chomp}" } if stderr && !stderr.empty?
        return nil
      end
      JSON.parse(stdout)
    rescue Errno::ENOENT
      warn "Warning: node not found; skipping mermaid syntax check"
      nil
    rescue JSON::ParserError
      warn "Warning: mermaid syntax check produced unexpected output; skipping"
      nil
    end
  end
end
