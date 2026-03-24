# frozen_string_literal: true

require "json"
require "time"
require "securerandom"
require "fileutils"

module Ligarb
  class ReviewStore
    def initialize(base_dir)
      @dir = File.join(base_dir, ".ligarb", "reviews")
      @mutex = Mutex.new
      FileUtils.mkdir_p(@dir)
    end

    def list
      @mutex.synchronize do
        Dir.glob(File.join(@dir, "*.json")).map { |f| read_json(f) }
          .compact
          .sort_by { |r| r["created_at"] }
          .map { |r| summary(r) }
      end
    end

    def get(id)
      @mutex.synchronize do
        get_unlocked(id)
      end
    end

    def create(context:, message:)
      @mutex.synchronize do
        id = SecureRandom.uuid
        now = Time.now.utc.iso8601

        review = {
          "id" => id,
          "status" => "open",
          "created_at" => now,
          "context" => context,
          "messages" => [
            { "role" => "user", "content" => message, "timestamp" => now }
          ]
        }

        write_json(id, review)
        review
      end
    end

    def add_message(id, role:, content:)
      @mutex.synchronize do
        review = get_unlocked(id)
        return nil unless review

        review["messages"] << {
          "role" => role,
          "content" => content,
          "timestamp" => Time.now.utc.iso8601
        }

        write_json(id, review)
        review
      end
    end

    def update_context_files(id, files)
      @mutex.synchronize do
        review = get_unlocked(id)
        return nil unless review

        existing = review.dig("context", "uploaded_files") || []
        review["context"]["uploaded_files"] = existing + files
        write_json(id, review)
        review
      end
    end

    def update_status(id, status)
      @mutex.synchronize do
        review = get_unlocked(id)
        return nil unless review

        review["status"] = status
        write_json(id, review)
        review
      end
    end

    def delete(id)
      @mutex.synchronize do
        path = file_path(id)
        return false unless File.exist?(path)
        File.delete(path)
        true
      end
    end

    private

    def get_unlocked(id)
      path = file_path(id)
      return nil unless File.exist?(path)
      review = read_json(path)
      review["file_path"] = path if review
      review
    end

    def file_path(id)
      File.join(@dir, "#{id}.json")
    end

    def read_json(path)
      JSON.parse(File.read(path))
    rescue JSON::ParserError
      nil
    end

    def write_json(id, data)
      File.write(file_path(id), JSON.pretty_generate(data))
    end

    def summary(review)
      {
        "id" => review["id"],
        "status" => review["status"],
        "created_at" => review["created_at"],
        "context" => review["context"],
        "message_count" => review["messages"].size,
        "last_message" => review["messages"].last
      }
    end
  end
end
