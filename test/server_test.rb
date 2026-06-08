# frozen_string_literal: true

require_relative "test_helper"
require "ligarb/server"

class ServerTest < Minitest::Test
  # Minimal stand-in for a WEBrick::HTTPRequest: responds to #request_method
  # and #[] for headers.
  FakeReq = Struct.new(:request_method, :headers) do
    def [](key)
      (headers || {})[key]
    end
  end

  def with_server(host: "127.0.0.1", port: 3000)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "book.yml"),
                 YAML.dump({"title" => "T", "chapters" => ["ch1.md"]}))
      File.write(File.join(dir, "ch1.md"), "# Ch\n\nHi")
      server = Ligarb::Server.new([File.join(dir, "book.yml")], host: host, port: port)
      yield server
    end
  end

  def post(headers)
    FakeReq.new("POST", headers)
  end

  def test_get_is_always_safe
    with_server do |s|
      assert s.send(:csrf_safe?, FakeReq.new("GET", {}))
    end
  end

  def test_same_origin_post_is_safe
    with_server do |s|
      assert s.send(:csrf_safe?, post("Host" => "localhost:3000",
                                      "Origin" => "http://localhost:3000"))
    end
  end

  def test_cross_origin_post_is_rejected
    with_server do |s|
      refute s.send(:csrf_safe?, post("Host" => "localhost:3000",
                                      "Origin" => "http://evil.example:3000"))
    end
  end

  def test_lan_bind_same_origin_post_is_safe
    with_server(host: "192.168.1.5") do |s|
      assert s.send(:csrf_safe?, post("Host" => "192.168.1.5:3000",
                                      "Origin" => "http://192.168.1.5:3000"))
    end
  end

  def test_referer_fallback_matches_host
    with_server do |s|
      assert s.send(:csrf_safe?, post("Host" => "localhost:3000",
                                      "Referer" => "http://localhost:3000/index.html"))
      refute s.send(:csrf_safe?, post("Host" => "localhost:3000",
                                      "Referer" => "http://evil.example/x"))
    end
  end

  def test_post_without_host_is_rejected
    with_server do |s|
      refute s.send(:csrf_safe?, post("Origin" => "http://localhost:3000"))
    end
  end

  def test_post_without_origin_or_referer_is_rejected
    with_server do |s|
      refute s.send(:csrf_safe?, post("Host" => "localhost:3000"))
    end
  end

  def test_display_host_collapses_wildcard_and_loopback
    with_server(host: "0.0.0.0") { |s| assert_equal "localhost", s.send(:display_host) }
    with_server(host: "127.0.0.1") { |s| assert_equal "localhost", s.send(:display_host) }
    with_server(host: "192.168.1.5") { |s| assert_equal "192.168.1.5", s.send(:display_host) }
  end

  def test_warn_if_exposed_only_beyond_loopback
    with_server(host: "127.0.0.1") do |s|
      _out, err = capture_subprocess_io { s.send(:warn_if_exposed) }
      assert_empty err
    end
    with_server(host: "0.0.0.0") do |s|
      _out, err = capture_subprocess_io { s.send(:warn_if_exposed) }
      assert_match(/exposes ligarb serve on the network/, err)
    end
  end
end
