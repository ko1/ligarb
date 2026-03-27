# frozen_string_literal: true

require "fileutils"
require_relative "config"
require_relative "chapter"
require_relative "template"
require_relative "asset_manager"

module Ligarb
  class Builder
    def initialize(config_path, parent_data: nil)
      @config = Config.new(config_path, parent_data: parent_data)
      @config_path = File.expand_path(config_path)
    end

    def build
      if @config.translations_hub?
        build_multilang
        return
      end

      structure = load_structure

      all_chapters = collect_all_chapters(structure)
      resolve_cross_references(all_chapters)
      assign_relative_paths(all_chapters) if @config.repository

      assets = AssetManager.new(@config.output_path)
      assets.detect(all_chapters)
      assets.provision!

      index_entries = all_chapters.flat_map { |ch|
        ch.index_entries.map { |e|
          e.class.new(term: e.term, display_text: e.display_text,
                      chapter_slug: e.chapter_slug, anchor_id: e.anchor_id)
        }
      }

      bibliography = resolve_citations!(all_chapters)

      html = Template.new.render(config: @config, chapters: all_chapters,
                                 structure: structure, assets: assets,
                                 index_entries: index_entries,
                                 bibliography: bibliography)

      FileUtils.mkdir_p(@config.output_path)
      output_file = File.join(@config.output_path, "index.html")
      File.write(output_file, html)

      copy_images

      puts "Built #{output_file}"
      puts "  #{all_chapters.size} chapter(s)"
    end

    private

    def build_multilang
      hub_data = @config.instance_variable_get(:@translations_data)
      hub_base = File.dirname(@config_path)
      output_dir = hub_data.fetch("output_dir", "build")
      output_path = File.join(hub_base, output_dir)

      langs = []
      all_lang_chapters = []

      @config.translations.each do |trans|
        child_config = Config.new(trans.config_path, parent_data: hub_data)
        prefix = "#{trans.lang}--"
        lang_data = build_language_data(trans.lang, child_config, prefix)
        langs << lang_data
        all_lang_chapters.concat(lang_data[:chapters])
      end

      assets = AssetManager.new(output_path)
      assets.detect(all_lang_chapters)
      assets.provision!

      html = Template.new.render_multilang(langs: langs, assets: assets,
                                           hub_data: hub_data)

      FileUtils.mkdir_p(output_path)
      output_file = File.join(output_path, "index.html")
      File.write(output_file, html)

      # Copy images from hub base dir
      images_dir = File.join(hub_base, "images")
      if Dir.exist?(images_dir)
        dest = File.join(output_path, "images")
        FileUtils.mkdir_p(dest)
        Dir.glob(File.join(images_dir, "*")).each { |img| FileUtils.cp(img, dest) }
      end

      puts "Built #{output_file}"
      langs.each { |ld| puts "  #{ld[:lang]}: #{ld[:chapters].size} chapter(s)" }
    end

    def build_language_data(lang, config, slug_prefix)
      @config = config
      structure = load_structure(slug_prefix: slug_prefix)
      all_chapters = collect_all_chapters(structure)
      resolve_cross_references(all_chapters)
      assign_relative_paths(all_chapters) if config.repository

      index_entries = all_chapters.flat_map { |ch|
        ch.index_entries.map { |e|
          e.class.new(term: e.term, display_text: e.display_text,
                      chapter_slug: e.chapter_slug, anchor_id: e.anchor_id)
        }
      }

      bibliography = resolve_citations!(all_chapters)

      {
        lang: lang,
        config: config,
        chapters: all_chapters,
        structure: structure,
        index_entries: index_entries,
        bibliography: bibliography,
      }
    end

    # StructNode mirrors Config::StructEntry but holds loaded Chapter objects
    StructNode = Struct.new(:type, :chapter, :children, keyword_init: true)

    def load_structure(slug_prefix: nil)
      chapter_num = 0
      appendix_num = 0

      @config.structure.map do |entry|
        case entry.type
        when :cover
          ch = load_chapter(entry.path, slug_prefix: slug_prefix)
          ch.cover = true
          StructNode.new(type: :cover, chapter: ch)
        when :chapter
          chapter_num += 1
          ch = load_chapter(entry.path, slug_prefix: slug_prefix)
          ch.number = chapter_num if @config.chapter_numbers
          StructNode.new(type: :chapter, chapter: ch)
        when :part
          part_ch = load_chapter(entry.path, slug_prefix: slug_prefix)
          part_ch.part_title = true
          children = (entry.children || []).map do |child|
            chapter_num += 1
            ch = load_chapter(child.path, slug_prefix: slug_prefix)
            ch.number = chapter_num if @config.chapter_numbers
            StructNode.new(type: :chapter, chapter: ch)
          end
          StructNode.new(type: :part, chapter: part_ch, children: children)
        when :appendix_group
          children = (entry.children || []).map do |child|
            appendix_num += 1
            ch = load_chapter(child.path, slug_prefix: slug_prefix)
            letter = ("A".ord + appendix_num - 1).chr
            ch.appendix_letter = letter if @config.chapter_numbers
            StructNode.new(type: :chapter, chapter: ch)
          end
          StructNode.new(type: :appendix_group, children: children)
        end
      end
    end

    def load_chapter(path, slug_prefix: nil)
      unless File.exist?(path)
        abort "Error: chapter not found: #{path}"
      end
      Chapter.new(path, @config.base_dir, slug_prefix: slug_prefix)
    end

    def collect_all_chapters(structure)
      structure.flat_map do |node|
        case node.type
        when :cover, :chapter
          [node.chapter]
        when :part
          [node.chapter] + (node.children || []).map(&:chapter)
        when :appendix_group
          (node.children || []).map(&:chapter)
        end
      end
    end

    def resolve_cross_references(all_chapters)
      chapter_map = {}
      all_chapters.each do |ch|
        abs_path = File.expand_path(ch.instance_variable_get(:@path))
        chapter_map[abs_path] = {
          slug: ch.slug,
          chapter: ch,
          headings: ch.headings.each_with_object({}) { |h, map| map[h.id] = h }
        }
      end

      all_chapters.each do |ch|
        ch.resolve_cross_references!(chapter_map)
      end
    end

    def assign_relative_paths(chapters)
      git_root = find_git_root(@config.base_dir)
      chapters.each do |ch|
        abs = File.expand_path(ch.instance_variable_get(:@path))
        ch.relative_path = if git_root
                             abs.sub("#{git_root}/", "")
                           else
                             abs.sub("#{File.expand_path(@config.base_dir)}/", "")
                           end
      end
    end

    def find_git_root(dir)
      dir = File.expand_path(dir)
      loop do
        return dir if File.directory?(File.join(dir, ".git"))
        parent = File.dirname(dir)
        return nil if parent == dir
        dir = parent
      end
    end

    def resolve_citations!(all_chapters)
      bib_path = @config.bibliography_path
      return [] unless bib_path

      unless File.exist?(bib_path)
        abort "Error: bibliography file not found: #{bib_path}"
      end

      bib_data = load_bibliography(bib_path)

      # Validate all cite keys exist
      cited_keys = {}
      all_chapters.each do |ch|
        ch.cite_entries.each do |entry|
          unless bib_data.key?(entry.key)
            warn "Warning: unknown bibliography key '#{entry.key}' in chapter #{File.basename(ch.instance_variable_get(:@path))}"
            next
          end
          cited_keys[entry.key] = true
        end
      end

      # Post-process each chapter's HTML to insert [author, year] citations
      all_chapters.each do |ch|
        ch.instance_variable_set(:@html, ch.html.gsub(%r{<span id="([^"]+)" data-cite-key="([^"]+)">(.*?)</span>}m) do
          anchor_id = $1
          key = $2
          display_text = $3
          ref = bib_data[key]
          unless ref
            next %(<span id="#{anchor_id}">#{display_text}<sup class="cite-ref cite-missing" title="Bibliography entry '#{encode_attr(key)}' not found">[#{encode_attr(key)}?]</sup></span>)
          end
          cite_label = format_cite_label(ref)
          title_text = format_bib_hover(ref)
          %(<span id="#{anchor_id}">#{display_text}<sup class="cite-ref"><a href="#bib-#{key}" title="#{encode_attr(title_text)}" onclick="showChapterAndScroll('__bibliography__', 'bib-#{key}'); return false;">[#{encode_attr(cite_label)}]</a></sup></span>)
        end)
      end

      # Build bibliography list sorted by author then year (only cited entries)
      cited_keys.keys.map do |key|
        ref = bib_data[key]
        {
          key: key,
          author: ref["author"],
          title: ref["title"],
          year: ref["year"],
          url: ref["url"],
          label: format_cite_label(ref),
          formatted_html: format_bib_html(ref),
        }
      end.sort_by { |e| [e[:author].to_s, e[:year].to_s] }
    end

    def load_bibliography(path)
      if path.end_with?(".bib")
        parse_bibtex(File.read(path))
      else
        YAML.safe_load_file(path)
      end
    end

    def parse_bibtex(source)
      result = {}
      # Remove comment lines
      lines = source.each_line.reject { |l| l.match?(/\A\s*%/) }.join

      # Extract @type{key, ...} blocks
      lines.scan(/@(\w+)\s*\{\s*([^,]+)\s*,(.*?)\n\s*\}/m) do |type, key, body|
        entry = {"_type" => type.downcase}
        body.scan(/(\w+)\s*=\s*(?:\{((?:[^{}]|\{(?:[^{}]|\{[^{}]*\})*\})*)\}|"([^"]*)")/) do |field, brace_val, quote_val|
          value = (brace_val || quote_val).strip
          # Remove BibTeX case-protection braces (e.g. {LaTeX} -> LaTeX)
          value = value.gsub(/\{([^{}]*)\}/, '\1')
          entry[field.downcase] = value
        end
        result[key.strip] = entry
      end

      result
    end

    def format_bib_html(ref)
      type = ref["_type"] || "misc"
      parts = []

      author = ref["author"]
      parts << encode_html(author) if author

      title = ref["title"]
      if title
        title_html = if ref["url"]
                       %(<em><a href="#{encode_attr(ref["url"])}" target="_blank" rel="noopener">#{encode_html(title)}</a></em>)
                     elsif type == "article" || type == "inproceedings"
                       %("#{encode_html(title)}")
                     else
                       "<em>#{encode_html(title)}</em>"
                     end
        parts << title_html
      end

      case type
      when "book"
        parts << "#{encode_html(ref["edition"])}" if ref["edition"]
        parts << encode_html(ref["publisher"]) if ref["publisher"]
      when "article"
        journal_parts = []
        journal_parts << "<em>#{encode_html(ref["journal"])}</em>" if ref["journal"]
        vol_num = []
        vol_num << ref["volume"] if ref["volume"]
        vol_num << "(#{ref["number"]})" if ref["number"]
        journal_parts << vol_num.join("") unless vol_num.empty?
        journal_parts << "pp. #{ref["pages"]}" if ref["pages"]
        parts << journal_parts.join(", ") unless journal_parts.empty?
      when "inproceedings"
        conf_parts = []
        conf_parts << "In <em>#{encode_html(ref["booktitle"])}</em>" if ref["booktitle"]
        conf_parts << "pp. #{ref["pages"]}" if ref["pages"]
        parts << conf_parts.join(", ") unless conf_parts.empty?
      else
        parts << encode_html(ref["publisher"]) if ref["publisher"]
        parts << "<em>#{encode_html(ref["journal"])}</em>" if ref["journal"]
        parts << "Vol. #{ref["volume"]}" if ref["volume"]
        parts << "pp. #{ref["pages"]}" if ref["pages"]
      end

      parts << ref["year"].to_s if ref["year"]
      parts << encode_html(ref["editor"]) if ref["editor"]
      parts << encode_html(ref["note"]) if ref["note"]

      # Strip trailing dots from parts to avoid double periods
      html = parts.map { |p| p.sub(/\.\z/, "") }.join(". ") + "."

      if ref["doi"] && !ref["url"]
        doi_url = ref["doi"].start_with?("http") ? ref["doi"] : "https://doi.org/#{ref["doi"]}"
        html += %( <a href="#{encode_attr(doi_url)}" target="_blank" rel="noopener">DOI</a>)
      elsif ref["doi"] && ref["url"]
        doi_url = ref["doi"].start_with?("http") ? ref["doi"] : "https://doi.org/#{ref["doi"]}"
        html += %( <a href="#{encode_attr(doi_url)}" target="_blank" rel="noopener">DOI</a>)
      end

      html
    end

    def format_cite_label(ref)
      author = ref["author"].to_s.split(/[,\s]/).first || "?"
      year = ref["year"] ? ref["year"].to_s : "n.d."
      "#{author}, #{year}"
    end

    def format_bib_hover(ref)
      parts = []
      parts << ref["author"] if ref["author"]
      parts << ref["title"] if ref["title"]
      parts << ref["publisher"] if ref["publisher"]
      parts << ref["journal"] if ref["journal"]
      parts << "Vol. #{ref["volume"]}" if ref["volume"]
      parts << "No. #{ref["number"]}" if ref["number"]
      parts << "pp. #{ref["pages"]}" if ref["pages"]
      parts << ref["edition"] if ref["edition"]
      parts << ref["year"].to_s if ref["year"]
      parts << ref["note"] if ref["note"]
      parts.join(". ") + "."
    end

    def encode_attr(text)
      text.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;").gsub('"', "&quot;")
    end

    def encode_html(text)
      text.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
    end

    def copy_images
      images_dir = File.join(@config.base_dir, "images")
      return unless Dir.exist?(images_dir)

      dest = File.join(@config.output_path, "images")
      FileUtils.mkdir_p(dest)

      Dir.glob(File.join(images_dir, "*")).each do |img|
        FileUtils.cp(img, dest)
      end
    end
  end
end
