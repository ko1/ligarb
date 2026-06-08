# frozen_string_literal: true

require "erb"
require "json"

module Ligarb
  class Template
    TEMPLATE_DIR = File.expand_path("../../templates", __dir__)
    ASSETS_DIR   = File.expand_path("../../assets", __dir__)

    def initialize
      @template_path = File.join(TEMPLATE_DIR, "book.html.erb")
      @css_path      = File.join(ASSETS_DIR, "style.css")
    end

    def render(config:, chapters:, structure:, assets:, index_entries: [], bibliography: [], github_review: nil)
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
      b.local_variable_set(:feedback, load_feedback(github_review))
      b.local_variable_set(:og_description, og_description(config, chapters))
      b.local_variable_set(:og_locale, og_locale(config.language))
      b.local_variable_set(:og_url, og_url(config))

      ERB.new(template, trim_mode: "-").result(b)
    end

    # Render a single HTML with all languages, switchable via JS
    def render_multilang(langs:, assets:, hub_data:, github_review: nil)
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
      b.local_variable_set(:feedback, load_feedback(github_review))
      b.local_variable_set(:og_description, og_description(first_config, first[:chapters]))
      b.local_variable_set(:og_locale, og_locale(first_config.language))
      b.local_variable_set(:og_url, og_url(first_config))

      ERB.new(template, trim_mode: "-").result(b)
    end

    private

    # When github_review (a hash with :base/:issue_template/:labels) is given,
    # returns the inlined feedback assets + a JSON config blob for the template
    # to embed; otherwise nil (the UI is not injected). Inlining keeps the build
    # output self-contained, like the main style.css.
    def load_feedback(github_review)
      return nil unless github_review

      config_json = JSON.generate(
        base: github_review[:base],
        issueTemplate: github_review[:issue_template],
        labels: github_review[:labels]
      ).gsub("</", '<\/')

      {
        css: File.read(File.join(ASSETS_DIR, "feedback.css")),
        js: File.read(File.join(ASSETS_DIR, "feedback.js")),
        config_json: config_json,
      }
    end

    # data-src-* attributes for a chapter <section>, used by the feedback UI to
    # locate the source Markdown. Empty unless the UI is active and the chapter
    # has a resolved source path (set when `repository` is configured).
    def src_attrs(chapter, feedback)
      return "" unless feedback && chapter.relative_path
      %( data-src-file="#{h(chapter.relative_path)}" data-src-title="#{h(chapter.display_title)}")
    end

    # HTML-escape helper for ERB templates (available via binding)
    def h(s)
      ERB::Util.html_escape(s.to_s)
    end

    # og:locale wants ll_CC; ligarb only knows the bare language code, so map
    # the common ones and fall back to the raw value for anything else.
    OG_LOCALES = { "ja" => "ja_JP", "en" => "en_US" }.freeze

    def og_locale(language)
      OG_LOCALES.fetch(language, language)
    end

    # Canonical URL for og:url, taken verbatim from `site_url` (the published
    # root of this build). Returns nil when unset so the tag is omitted — a
    # wrong canonical URL is worse than none.
    def og_url(config)
      url = config.site_url.to_s.strip
      url.empty? ? nil : url
    end

    # Resolve the OGP description: the configured `description`, or, failing
    # that, the first real paragraph of prose from the cover (or first) chapter.
    # Returns nil when nothing usable is found.
    def og_description(config, chapters)
      explicit = config.description.to_s.strip
      return explicit unless explicit.empty?

      auto_description(chapters)
    end

    DESCRIPTION_LIMIT = 200

    def auto_description(chapters)
      chapter = chapters.find(&:cover?) || chapters.first
      return nil unless chapter

      # First <p> with real prose (tags stripped, whitespace collapsed).
      # Image-only paragraphs (e.g. a cover logo) strip to empty and are skipped.
      chapter.html.scan(%r{<p[^>]*>(.*?)</p>}m) do |(inner)|
        text = inner.gsub(/<[^>]+>/, "").gsub(/\s+/, " ").strip
        text = text.gsub("&amp;", "&").gsub("&lt;", "<").gsub("&gt;", ">").gsub("&quot;", '"').gsub("&#39;", "'")
        next if text.empty?

        return text.length > DESCRIPTION_LIMIT ? "#{text[0, DESCRIPTION_LIMIT - 1].rstrip}…" : text
      end

      nil
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
