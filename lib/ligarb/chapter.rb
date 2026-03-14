# frozen_string_literal: true

require "kramdown"
require "kramdown-parser-gfm"

module Ligarb
  class Chapter
    attr_reader :title, :slug, :html, :headings, :number, :appendix_letter
    attr_accessor :part_title, :cover, :relative_path

    Heading = Struct.new(:level, :text, :id, :display_text, keyword_init: true)

    def initialize(path, base_dir)
      @path     = path
      @base_dir = base_dir
      @source   = File.read(path)
      @number   = nil
      @appendix_letter = nil
      @part_title = false
      @cover = false

      @relative_path = nil
      @slug = File.basename(path, ".md").gsub(/[^a-zA-Z0-9_-]/, "-")
      parse!
    end

    def number=(n)
      @number = n
      apply_section_numbers! if n
    end

    def appendix_letter=(letter)
      @appendix_letter = letter
      apply_appendix_numbers!(letter) if letter
    end

    def part_title?
      @part_title
    end

    def cover?
      @cover
    end

    def display_title
      if @appendix_letter
        "#{@appendix_letter}. #{@title}"
      elsif @number
        "#{@number}. #{@title}"
      else
        @title
      end
    end

    private

    def parse!
      doc = Kramdown::Document.new(@source, input: "GFM", hard_wrap: false)
      @headings = extract_headings(doc.root)
      @html = rewrite_image_paths(doc.to_html)
      @html = apply_heading_ids(@html)
      @html = convert_special_code_blocks(@html)
      @html = scope_footnote_ids(@html)
      @title = @headings.first&.text || @slug
    end

    def extract_headings(root)
      headings = []
      walk(root) do |el|
        if el.type == :header && el.options[:level] <= 3
          text = extract_text(el)
          id = generate_id(text)
          headings << Heading.new(level: el.options[:level], text: text, id: id, display_text: text)
        end
      end
      headings
    end

    def walk(el, &block)
      yield el
      el.children.each { |child| walk(child, &block) } if el.respond_to?(:children)
    end

    def extract_text(el)
      if el.respond_to?(:children) && !el.children.empty?
        el.children.map { |c| extract_text(c) }.join
      elsif el.type == :text || el.type == :codespan
        el.value
      else
        ""
      end
    end

    def generate_id(text)
      text.downcase
          .gsub(/[^\p{L}\p{N}\s_-]/u, "") # keep letters (any script), digits, spaces, _, -
          .strip
          .gsub(/\s+/, "-")
    end

    def apply_heading_ids(html)
      heading_index = 0
      html.gsub(%r{<(h[123])(\s[^>]*)?>}m) do
        tag = $1
        attrs = $2 || ""
        if heading_index < @headings.length
          full_id = "#{@slug}--#{@headings[heading_index].id}"
          heading_index += 1
          # Replace existing id or add new one
          if attrs =~ /id="/
            "<#{tag}#{attrs.sub(/id="[^"]*"/, "id=\"#{full_id}\"")}>".squeeze(" ")
          else
            "<#{tag} id=\"#{full_id}\"#{attrs}>"
          end
        else
          "<#{tag}#{attrs}>"
        end
      end
    end

    def convert_special_code_blocks(html)
      html.gsub(%r{<pre><code class="language-(mermaid|math)">(.*?)</code></pre>}m) do
        lang = $1
        raw = decode_entities($2)
        case lang
        when "mermaid"
          %(<div class="mermaid">\n#{raw}</div>)
        when "math"
          %(<div class="math-block" data-math="#{encode_attr(raw)}"></div>)
        end
      end
    end

    def decode_entities(text)
      text.gsub("&amp;", "&").gsub("&lt;", "<").gsub("&gt;", ">").gsub("&quot;", '"').gsub("&#39;", "'")
    end

    def encode_attr(text)
      text.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;").gsub('"', "&quot;")
    end

    def scope_footnote_ids(html)
      html.gsub(/(id="|href="#)(fn:|fnref:)(\w+)/) do
        "#{$1}#{$2}#{@slug}--#{$3}"
      end
    end

    def rewrite_image_paths(html)
      html.gsub(/(<img\s[^>]*src=")([^"]+)(")/) do
        prefix = $1
        src    = $2
        suffix = $3

        if src.start_with?("http://", "https://", "data:")
          "#{prefix}#{src}#{suffix}"
        else
          basename = File.basename(src)
          "#{prefix}images/#{basename}#{suffix}"
        end
      end
    end

    def apply_appendix_numbers!(letter)
      h2_count = 0
      h3_count = 0

      @headings.each do |heading|
        case heading.level
        when 1
          heading.display_text = "#{letter}. #{heading.text}"
        when 2
          h2_count += 1
          h3_count = 0
          heading.display_text = "#{letter}.#{h2_count} #{heading.text}"
        when 3
          h3_count += 1
          heading.display_text = "#{letter}.#{h2_count}.#{h3_count} #{heading.text}"
        end
      end

      h2_count = 0
      h3_count = 0
      @html = @html.gsub(%r{<(h[123])(\s[^>]*)?>(.+?)</\1>}m) do
        tag = $1
        attrs = $2 || ""
        content = $3

        numbered = case tag
        when "h1"
          "#{letter}. #{content}"
        when "h2"
          h2_count += 1
          h3_count = 0
          "#{letter}.#{h2_count} #{content}"
        when "h3"
          h3_count += 1
          "#{letter}.#{h2_count}.#{h3_count} #{content}"
        end

        "<#{tag}#{attrs}>#{numbered}</#{tag}>"
      end
    end

    def apply_section_numbers!
      h2_count = 0
      h3_count = 0

      @headings.each do |heading|
        case heading.level
        when 1
          heading.display_text = "#{@number}. #{heading.text}"
        when 2
          h2_count += 1
          h3_count = 0
          heading.display_text = "#{@number}.#{h2_count} #{heading.text}"
        when 3
          h3_count += 1
          heading.display_text = "#{@number}.#{h2_count}.#{h3_count} #{heading.text}"
        end
      end

      # Rewrite HTML headings to include section numbers
      h2_count = 0
      h3_count = 0
      @html = @html.gsub(%r{<(h[123])(\s[^>]*)?>(.+?)</\1>}m) do
        tag = $1
        attrs = $2 || ""
        content = $3

        numbered = case tag
        when "h1"
          "#{@number}. #{content}"
        when "h2"
          h2_count += 1
          h3_count = 0
          "#{@number}.#{h2_count} #{content}"
        when "h3"
          h3_count += 1
          "#{@number}.#{h2_count}.#{h3_count} #{content}"
        end

        "<#{tag}#{attrs}>#{numbered}</#{tag}>"
      end
    end
  end
end
