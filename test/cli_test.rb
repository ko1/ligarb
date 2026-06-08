# frozen_string_literal: true

require_relative "test_helper"
require "ligarb/cli"

class CliTest < Minitest::Test
  def test_parse_host_defaults_to_loopback
    assert_equal ["127.0.0.1", nil], Ligarb::CLI.parse_host([])
    assert_equal ["127.0.0.1", nil], Ligarb::CLI.parse_host(["book.yml", "--port", "8080"])
  end

  def test_parse_host_reads_value_and_index
    assert_equal ["0.0.0.0", 0], Ligarb::CLI.parse_host(["--host", "0.0.0.0"])
    host, idx = Ligarb::CLI.parse_host(["book.yml", "--host", "192.168.1.5"])
    assert_equal "192.168.1.5", host
    assert_equal 1, idx
  end

  def test_parse_host_aborts_on_missing_value
    assert_raises(SystemExit) do
      capture_io { Ligarb::CLI.parse_host(["--host"]) }
    end
    assert_raises(SystemExit) do
      capture_io { Ligarb::CLI.parse_host(["--host", "--port"]) }
    end
  end

  def test_parse_port_defaults_and_reads
    assert_equal [3000, nil], Ligarb::CLI.parse_port([])
    assert_equal [8080, 0], Ligarb::CLI.parse_port(["--port", "8080"])
  end

  def test_parse_port_rejects_out_of_range
    assert_raises(SystemExit) { capture_io { Ligarb::CLI.parse_port(["--port", "0"]) } }
    assert_raises(SystemExit) { capture_io { Ligarb::CLI.parse_port(["--port", "70000"]) } }
  end
end
