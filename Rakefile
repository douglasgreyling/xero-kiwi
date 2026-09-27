# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

require "rubocop/rake_task"

RuboCop::RakeTask.new

require_relative "tasks/llms"

namespace :llms do
  desc "Regenerate llms.txt and llms-full.txt from README and docs/"
  task :build do
    Llms.outputs.each do |path, content|
      File.write(path, content)
      puts "Wrote #{path} (#{File.size(path)} bytes)"
    end
  end

  desc "Verify llms.txt and llms-full.txt are up to date, and that every doc is indexed"
  task :check do
    missing = Llms.unindexed_docs
    unless missing.empty?
      warn "✗ These docs are not listed in Llms::DOCS, so they are missing from llms.txt and llms-full.txt:"
      missing.each { |path| warn "    #{path}" }
      warn "  Add them to tasks/llms.rb and run `bundle exec rake llms:build`."
      exit 1
    end

    stale = Llms.outputs.reject do |path, expected|
      File.exist?(path) && File.read(path, encoding: "UTF-8") == expected
    end

    if stale.empty?
      puts "✓ llms.txt and llms-full.txt are up to date"
    else
      warn "✗ Out of date with README/docs: #{stale.keys.join(", ")}"
      warn "  Run `bundle exec rake llms:build` and commit the result."
      exit 1
    end
  end
end

# Top-level convenience alias.
desc "Regenerate the LLM docs bundles (alias for llms:build)"
task llms: "llms:build"

task default: %i[spec rubocop llms:check]
