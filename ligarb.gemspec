# frozen_string_literal: true

require_relative "lib/ligarb/version"

Gem::Specification.new do |spec|
  spec.name          = "ligarb"
  spec.version       = Ligarb::VERSION
  spec.authors       = ["ligarb contributors"]
  spec.summary       = "Generate a single-page HTML book from Markdown files"
  spec.description   = "A CLI tool that converts multiple Markdown files into a self-contained index.html with a searchable table of contents sidebar and chapter navigation."
  spec.homepage      = "https://github.com/ligarb/ligarb"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.0"

  # FNM_DOTMATCH is needed so the generated .github/ templates (a dot-directory)
  # are packaged; reject directory entries (incl. "." / "..") so only files ship.
  spec.files         = (
    Dir["lib/**/*.rb", "exe/*", "templates/*", "assets/*", "docs/help.md"] +
    Dir.glob("templates/github_review/**/*", File::FNM_DOTMATCH)
  ).reject { |f| File.directory?(f) }.uniq
  spec.bindir        = "exe"
  spec.executables   = ["ligarb"]

  spec.add_dependency "kramdown", "~> 2.4"
  spec.add_dependency "kramdown-parser-gfm", "~> 1.1"
  spec.add_dependency "webrick", ">= 1.7"
  spec.add_dependency "fiddle", ">= 1.1"
  # base64 left the default gems in Ruby 3.4 / became unbundled in 3.5+;
  # server.rb requires it, so depend on it explicitly.
  spec.add_dependency "base64", ">= 0.1"

  spec.add_development_dependency "rake"
  spec.add_development_dependency "minitest"
end
