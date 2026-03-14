# frozen_string_literal: true

require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
end

desc "Build the example book"
task :example do
  ruby "exe/ligarb build example/book.yml"
end

task default: :test
