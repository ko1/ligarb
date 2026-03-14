# frozen_string_literal: true

require "fileutils"
require_relative "config"
require_relative "chapter"
require_relative "template"
require_relative "asset_manager"

module Ligarb
  class Builder
    def initialize(config_path)
      @config = Config.new(config_path)
    end

    def build
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

      html = Template.new.render(config: @config, chapters: all_chapters,
                                 structure: structure, assets: assets,
                                 index_entries: index_entries)

      FileUtils.mkdir_p(@config.output_path)
      output_file = File.join(@config.output_path, "index.html")
      File.write(output_file, html)

      copy_images

      puts "Built #{output_file}"
      puts "  #{all_chapters.size} chapter(s)"
    end

    private

    # StructNode mirrors Config::StructEntry but holds loaded Chapter objects
    StructNode = Struct.new(:type, :chapter, :children, keyword_init: true)

    def load_structure
      chapter_num = 0
      appendix_num = 0

      @config.structure.map do |entry|
        case entry.type
        when :cover
          ch = load_chapter(entry.path)
          ch.cover = true
          StructNode.new(type: :cover, chapter: ch)
        when :chapter
          chapter_num += 1
          ch = load_chapter(entry.path)
          ch.number = chapter_num if @config.chapter_numbers
          StructNode.new(type: :chapter, chapter: ch)
        when :part
          part_ch = load_chapter(entry.path)
          part_ch.part_title = true
          children = (entry.children || []).map do |child|
            chapter_num += 1
            ch = load_chapter(child.path)
            ch.number = chapter_num if @config.chapter_numbers
            StructNode.new(type: :chapter, chapter: ch)
          end
          StructNode.new(type: :part, chapter: part_ch, children: children)
        when :appendix_group
          children = (entry.children || []).map do |child|
            appendix_num += 1
            ch = load_chapter(child.path)
            letter = ("A".ord + appendix_num - 1).chr
            ch.appendix_letter = letter if @config.chapter_numbers
            StructNode.new(type: :chapter, chapter: ch)
          end
          StructNode.new(type: :appendix_group, children: children)
        end
      end
    end

    def load_chapter(path)
      unless File.exist?(path)
        abort "Error: chapter not found: #{path}"
      end
      Chapter.new(path, @config.base_dir)
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
