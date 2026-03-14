# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "yaml"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "ligarb/config"
require "ligarb/chapter"
require "ligarb/builder"
