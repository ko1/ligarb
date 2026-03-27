# frozen_string_literal: true

require "erb"

module Ligarb
  class Template
    TEMPLATE_DIR = File.expand_path("../../templates", __dir__)
    ASSETS_DIR   = File.expand_path("../../assets", __dir__)

    def initialize
      @template_path = File.join(TEMPLATE_DIR, "book.html.erb")
      @css_path      = File.join(ASSETS_DIR, "style.css")
    end

    def render(config:, chapters:, structure:, assets:, index_entries: [], bibliography: [])
      css = File.read(@css_path)
      template = File.read(@template_path)

      custom_css = if config.style_path && File.exist?(config.style_path)
                     File.read(config.style_path)
                   end

      b = binding
      b.local_variable_set(:title, config.title)
      b.local_variable_set(:author, config.author)
      b.local_variable_set(:language, config.language)
      b.local_variable_set(:chapters, chapters)
      b.local_variable_set(:structure, structure)
      b.local_variable_set(:css, css)
      b.local_variable_set(:custom_css, custom_css)
      b.local_variable_set(:assets, assets)
      b.local_variable_set(:repository, config.repository)
      b.local_variable_set(:appendix_label, config.appendix_label)
      b.local_variable_set(:ai_generated, config.ai_generated)
      b.local_variable_set(:footer, config.effective_footer)
      b.local_variable_set(:index_tree, build_index_tree(index_entries, chapters))
      b.local_variable_set(:bibliography, bibliography)
      b.local_variable_set(:multilang, false)
      b.local_variable_set(:langs, [])

      ERB.new(template, trim_mode: "-").result(b)
    end

    # Render a single HTML with all languages, switchable via JS
    def render_multilang(langs:, assets:, hub_data:)
      css = File.read(@css_path)
      template = File.read(@template_path)

      first = langs.first
      first_config = first[:config]

      custom_css = if first_config.style_path && File.exist?(first_config.style_path)
                     File.read(first_config.style_path)
                   end

      # Build per-language template data
      lang_data = langs.map do |ld|
        cfg = ld[:config]
        {
          lang: ld[:lang],
          title: cfg.title,
          author: cfg.author,
          language: cfg.language,
          chapters: ld[:chapters],
          structure: ld[:structure],
          repository: cfg.repository,
          appendix_label: cfg.appendix_label,
          ai_generated: cfg.ai_generated,
          footer: cfg.effective_footer,
          index_tree: build_index_tree(ld[:index_entries], ld[:chapters]),
          bibliography: ld[:bibliography],
        }
      end

      b = binding
      # Use first language's values as defaults for shared template vars
      b.local_variable_set(:title, first_config.title)
      b.local_variable_set(:author, first_config.author)
      b.local_variable_set(:language, first_config.language)
      b.local_variable_set(:chapters, first[:chapters])
      b.local_variable_set(:structure, first[:structure])
      b.local_variable_set(:css, css)
      b.local_variable_set(:custom_css, custom_css)
      b.local_variable_set(:assets, assets)
      b.local_variable_set(:repository, first_config.repository)
      b.local_variable_set(:appendix_label, first_config.appendix_label)
      b.local_variable_set(:ai_generated, first_config.ai_generated)
      b.local_variable_set(:footer, first_config.effective_footer)
      b.local_variable_set(:index_tree, build_index_tree(first[:index_entries], first[:chapters]))
      b.local_variable_set(:bibliography, first[:bibliography])
      b.local_variable_set(:multilang, true)
      b.local_variable_set(:langs, lang_data)

      ERB.new(template, trim_mode: "-").result(b)
    end

    private

    # HTML-escape helper for ERB templates (available via binding)
    def h(s)
      ERB::Util.html_escape(s.to_s)
    end

    # Build a sorted tree structure for the index.
    # Returns: { "A" => [ { term: "Algorithm", refs: [...] },
    #                      { term: "Array", refs: [...], children: [ { term: "sort", refs: [...] } ] } ],
    #            ... }
    def build_index_tree(entries, chapters)
      return {} if entries.empty?

      chapter_titles = chapters.each_with_object({}) { |ch, h| h[ch.slug] = ch.display_title }

      # Group by full term, collecting refs
      term_refs = {}
      entries.each do |e|
        parts = e.term.split("/", 2)
        top = parts[0]
        sub = parts[1]

        key = sub ? [top, sub] : [top]
        term_refs[key] ||= []
        term_refs[key] << { chapter_slug: e.chapter_slug,
                            chapter_title: chapter_titles[e.chapter_slug] || e.chapter_slug,
                            anchor_id: e.anchor_id }
      end

      # Build nested structure grouped by first character
      nested = {}
      term_refs.each do |key, refs|
        top = key[0]
        sub = key[1]

        nested[top] ||= { refs: [], children: {} }
        if sub
          nested[top][:children][sub] ||= []
          nested[top][:children][sub].concat(refs)
        else
          nested[top][:refs].concat(refs)
        end
      end

      # Group by first character and sort
      grouped = {}
      nested.sort_by { |k, _| k }.each do |term, data|
        letter = first_letter(term)
        grouped[letter] ||= []
        children = data[:children].sort_by { |k, _| k }.map { |k, v| { term: k, refs: v } }
        grouped[letter] << { term: term, refs: data[:refs], children: children }
      end

      grouped
    end

    def first_letter(term)
      ch = term[0]
      if ch&.match?(/[a-zA-Z]/)
        ch.upcase
      elsif ch&.match?(/\p{Hiragana}|\p{Katakana}/)
        ch
      else
        ch || "#"
      end
    end
  end
end
