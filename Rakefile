# frozen_string_literal: true


require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
end

desc "Build the manual book (all languages)"
task :manual do
  ruby "exe/ligarb build manual/book.yml"
  ruby "exe/ligarb build manual/book.ja.yml"
  ruby "exe/ligarb build manual/book.en.yml"
end

task default: [:test, :manual]