# frozen_string_literal: true

require "net/http"
require "uri"
require "fileutils"
require "set"

module Ligarb
  class AssetManager
    ASSETS = {
      highlight: {
        fence_pattern: /language-(?!mermaid|math)(\w+)/,
        files: {
          "js/highlight.min.js" => "https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.11.1/highlight.min.js",
          "css/highlight.css" => "https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.11.1/styles/github.min.css",
        },
      },
      mermaid: {
        fence_pattern: /class="mermaid"/,
        files: {
          "js/mermaid.min.js" => "https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js",
        },
      },
      katex: {
        fence_pattern: /class="math-(block|inline)"/,
        files: {
          "js/katex.min.js" => "https://cdn.jsdelivr.net/npm/katex@0.16/dist/katex.min.js",
          "css/katex.min.css" => "https://cdn.jsdelivr.net/npm/katex@0.16/dist/katex.min.css",
        },
      },
    }.freeze

    def initialize(output_path)
      @output_path = output_path
      @needed = Set.new
    end

    # Scan chapter HTML to detect which assets are needed
    def detect(chapters)
      combined_html = chapters.map(&:html).join
      ASSETS.each do |name, config|
        @needed << name if combined_html.match?(config[:fence_pattern])
      end
      @needed
    end

    # Download assets if not already present
    def provision!
      @needed.each do |name|
        ASSETS[name][:files].each do |dest_rel, url|
          dest = File.join(@output_path, dest_rel)
          download(url, dest) unless File.exist?(dest)
        end
      end
    end

    def need?(name)
      @needed.include?(name)
    end

    private

    def download(url, dest)
      FileUtils.mkdir_p(File.dirname(dest))
      $stderr.print "Downloading #{File.basename(dest)}... "

      uri = URI(url)
      response = fetch_with_redirects(uri)

      if response.is_a?(Net::HTTPSuccess)
        File.write(dest, response.body)
        $stderr.puts "done"
      else
        abort "Error: failed to download #{url} (#{response.code})"
      end
    end

    def fetch_with_redirects(uri, limit = 5)
      raise "Too many redirects" if limit == 0

      response = Net::HTTP.get_response(uri)
      case response
      when Net::HTTPRedirection
        fetch_with_redirects(URI(response["location"]), limit - 1)
      else
        response
      end
    end
  end
end
