# frozen_string_literal: true

require "kramdown"
require "kramdown-parser-gfm"

module Ligarb
  class Chapter
    class CrossReferenceError < StandardError; end

    attr_reader :title, :slug, :html, :headings, :number, :appendix_letter, :index_entries, :cite_entries
    attr_accessor :part_title, :cover, :relative_path

    Heading = Struct.new(:level, :text, :id, :display_text, keyword_init: true)
    IndexEntry = Struct.new(:term, :display_text, :chapter_slug, :anchor_id, keyword_init: true)
    CiteEntry = Struct.new(:key, :display_text, :chapter_slug, :anchor_id, keyword_init: true)

    def initialize(path, base_dir, slug_prefix: nil)
      @path     = path
      @base_dir = base_dir
      @source   = File.read(path)
      @number   = nil
      @appendix_letter = nil
      @part_title = false
      @cover = false

      @relative_path = nil
      base_slug = File.basename(path, ".md").gsub(/[^a-zA-Z0-9_-]/, "-")
      @slug = slug_prefix ? "#{slug_prefix}#{base_slug}" : base_slug
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

    def self.generate_id(text)
      text.downcase
          .gsub(/[^\p{L}\p{N}\s_-]/u, "")
          .strip
          .gsub(/\s+/, "-")
    end

    def resolve_cross_references!(chapter_map)
      source_dir = File.dirname(@path)

      @html = @html.gsub(%r{<a\s+href="((?!https?://)[^"]+\.md)(?:#([^"]*))?">(.*?)</a>}m) do
        href_path = $1
        fragment = $2
        link_text = $3

        target_path = File.expand_path(href_path, source_dir)
        entry = chapter_map[target_path]
        unless entry
          line_no = @source.each_line.with_index(1) { |line, i| break i if line.include?(href_path) }
          loc = line_no ? "#{@path}:#{line_no}" : File.basename(@path)
          raise CrossReferenceError, "cross-reference target not found: #{href_path} (from #{loc})\n  link text: #{link_text.empty? ? "(auto)" : link_text}\n  resolved to: #{target_path}"
        end

        if fragment && !fragment.empty?
          normalized = self.class.generate_id(fragment)
          heading = entry[:headings][normalized]
          unless heading
            raise CrossReferenceError, "cross-reference heading not found: #{href_path}##{fragment} (from #{File.basename(@path)})"
          end
          anchor = "#{entry[:slug]}--#{heading.id}"
          text = link_text.empty? ? heading.display_text : link_text
        else
          anchor = entry[:slug]
          text = link_text.empty? ? entry[:chapter].display_title : link_text
        end

        %(<a href="##{anchor}">#{text}</a>)
      end
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
      @html = convert_inline_math(@html)
      @html = convert_admonitions(@html)
      @html = scope_footnote_ids(@html)
      @index_entries = []
      @html = extract_index_markers(@html)
      @cite_entries = []
      @html = extract_cite_markers(@html)
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
      self.class.generate_id(text)
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
      html.gsub(%r{<pre><code class="language-(mermaid|math|functionplot)">(.*?)</code></pre>}m) do
        lang = $1
        raw = decode_entities($2)
        case lang
        when "mermaid"
          escaped = raw.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
          %(<div class="mermaid">\n#{raw}</div>) +
            %(<details class="mermaid-source"><summary>mermaid source</summary><pre>#{escaped}</pre></details>)
        when "math"
          %(<div class="math-block" data-math="#{encode_attr(raw)}"></div>)
        when "functionplot"
          %(<div class="functionplot" data-plot="#{encode_attr(raw)}"></div>)
        end
      end
    end

    def convert_inline_math(html)
      # Protect <pre>...</pre> and <code>...</code> from conversion
      placeholders = []
      protected = html.gsub(%r{<(pre|code)([ >])(.*?)</\1>}m) do
        placeholders << $&
        "\x00PROTECT#{placeholders.size - 1}\x00"
      end

      # Convert $...$ to inline math (exclude $$, and $ followed/preceded by space)
      # Inline math must be on a single line (no /m flag) to avoid $200 etc. matching across lines
      result = protected.gsub(/(?<!\$)\$(?!\$)(?!\s)(.+?)(?<!\s)(?<!\$)\$(?!\$)/) do
        raw = decode_entities($1)
        %(<span class="math-inline" data-math="#{encode_attr(raw)}"></span>)
      end

      # Restore protected parts
      result.gsub(/\x00PROTECT(\d+)\x00/) { placeholders[$1.to_i] }
    end

    def decode_entities(text)
      text.gsub("&amp;", "&").gsub("&lt;", "<").gsub("&gt;", ">").gsub("&quot;", '"').gsub("&#39;", "'")
    end

    def encode_attr(text)
      text.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;").gsub('"', "&quot;")
    end

    ADMONITION_TITLES = {
      "NOTE" => "Note",
      "TIP" => "Tip",
      "WARNING" => "Warning",
      "CAUTION" => "Caution",
      "IMPORTANT" => "Important",
    }.freeze

    def convert_admonitions(html)
      html.gsub(%r{<blockquote>\s*<p>\[!(NOTE|TIP|WARNING|CAUTION|IMPORTANT)\]\s*\n?(.*?)</p>(.*?)</blockquote>}m) do
        type = $1
        first_content = $2.strip
        rest = $3
        css_class = type.downcase
        title = ADMONITION_TITLES[type]

        inner = if first_content.empty?
                  rest
                else
                  "<p>#{first_content}</p>#{rest}"
                end

        %(<div class="admonition admonition-#{css_class}">\n<p class="admonition-title">#{title}</p>\n#{inner}</div>)
      end
    end

    def scope_footnote_ids(html)
      html.gsub(/(id="|href="#)(fn:|fnref:)(\w+)/) do
        "#{$1}#{$2}#{@slug}--#{$3}"
      end
    end

    def extract_index_markers(html)
      idx_count = 0
      html.gsub(%r{<a\s+href="#index(?::([^"]*))?">(.*?)</a>}m) do
        terms_str = $1
        display_text = $2
        anchor_id = "#{@slug}--idx-#{idx_count}"
        idx_count += 1

        terms = if terms_str && !terms_str.empty?
                  terms_str.split(",").map(&:strip)
                else
                  [display_text.gsub(/<[^>]+>/, "")]  # strip any HTML tags for the term
                end

        terms.each do |term|
          @index_entries << IndexEntry.new(
            term: term,
            display_text: display_text,
            chapter_slug: @slug,
            anchor_id: anchor_id
          )
        end

        %(<span id="#{anchor_id}">#{display_text}</span>)
      end
    end

    def extract_cite_markers(html)
      cite_count = 0
      html.gsub(%r{<a\s+href="#cite:([^"]+)">(.*?)</a>}m) do
        key = $1
        display_text = $2
        anchor_id = "#{@slug}--cite-#{cite_count}"
        cite_count += 1

        @cite_entries << CiteEntry.new(
          key: key,
          display_text: display_text,
          chapter_slug: @slug,
          anchor_id: anchor_id
        )

        %(<span id="#{anchor_id}" data-cite-key="#{key}">#{display_text}</span>)
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
