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

    def render(config:, chapters:, structure:, assets:)
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

      ERB.new(template, trim_mode: "-").result(b)
    end
  end
end
