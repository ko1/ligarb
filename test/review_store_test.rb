# frozen_string_literal: true

require_relative "test_helper"
require "ligarb/review_store"

class ReviewStoreTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @store = Ligarb::ReviewStore.new(@dir)
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_create_and_get
    review = @store.create(
      context: { "chapter_slug" => "ch1", "selected_text" => "hello" },
      message: "Fix this"
    )

    assert review["id"]
    assert_equal "open", review["status"]
    assert_equal 1, review["messages"].size
    assert_equal "user", review["messages"][0]["role"]
    assert_equal "Fix this", review["messages"][0]["content"]

    fetched = @store.get(review["id"])
    assert_equal review["id"], fetched["id"]
    assert_equal "hello", fetched["context"]["selected_text"]
  end

  def test_list
    @store.create(context: {}, message: "First")
    @store.create(context: {}, message: "Second")

    list = @store.list
    assert_equal 2, list.size
    assert list.all? { |r| r.key?("message_count") }
  end

  def test_add_message
    review = @store.create(context: {}, message: "Initial")
    @store.add_message(review["id"], role: "assistant", content: "Suggestion")

    updated = @store.get(review["id"])
    assert_equal 2, updated["messages"].size
    assert_equal "assistant", updated["messages"][1]["role"]
    assert_equal "Suggestion", updated["messages"][1]["content"]
  end

  def test_update_status
    review = @store.create(context: {}, message: "Test")
    @store.update_status(review["id"], "applied")

    updated = @store.get(review["id"])
    assert_equal "applied", updated["status"]
  end

  def test_delete
    review = @store.create(context: {}, message: "Test")
    assert @store.delete(review["id"])
    assert_nil @store.get(review["id"])
  end

  def test_delete_nonexistent
    refute @store.delete("nonexistent-id")
  end

  def test_add_message_nonexistent
    assert_nil @store.add_message("nonexistent", role: "user", content: "test")
  end
end
