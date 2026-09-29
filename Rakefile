# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

require "rubocop/rake_task"

RuboCop::RakeTask.new

require_relative "tasks/llms"
require_relative "tasks/coverage"
require_relative "tasks/schema"

namespace :xero do
  desc "Compare every recorded Xero response against the resources that model it"
  task :coverage do
    $LOAD_PATH.unshift File.expand_path("lib", __dir__)
    require "xero_kiwi"

    report = Coverage.survey

    puts "Keys Xero sends that nothing models"
    puts "-" * 70
    Coverage.unmodelled(report).sort_by { |klass, _| klass.name }.each do |klass, rows|
      puts "\n  #{Coverage.short(klass)} (#{report[:seen][klass]} recorded)"
      rows.each do |key, populated, total|
        state = populated.positive? ? "populated #{populated}/#{total}" : "always empty"
        puts format("    %-30<key>s %<state>s", key: key, state: state)
      end
    end

    puts "\n\nAttributes nil in every recording"
    puts "-" * 70
    puts "  A wrong `xero:` key is indistinguishable from a field this tenant never fills."
    Coverage.unpopulated(report).sort_by { |klass, _| klass.name }.each do |klass, names|
      puts "\n  #{Coverage.short(klass)} (#{report[:seen][klass]} recorded)"
      names.each do |name|
        puts format("    %-30<name>s -> %<key>s", name: name, key: klass.attributes[name][:xero].inspect)
      end
    end

    puts "\n\nDeclared type against what Xero sends"
    puts "-" * 70
    Coverage.mistyped(report).sort_by { |klass, _| klass.name }.each do |klass, rows|
      puts "\n  #{Coverage.short(klass)}"
      rows.each do |name, type, counts|
        actual = counts.map { |cls, n| "#{cls} x#{n}" }.join(", ")
        puts format("    %-26<name>s declared %-9<type>s got %<actual>s",
                    name: name, type: type.inspect, actual: actual)
      end
    end

    puts "\n\nClasses no cassette here exercises"
    puts "-" * 70
    Coverage.unexercised(report).sort_by(&:name).each do |klass|
      short = Coverage.short(klass)
      note  = Coverage::CONFIRMED_ELSEWHERE[short]
      puts note ? "    #{short} — confirmed elsewhere: #{note}" : "    #{short} — unverified"
    end
    puts
  end

  desc "Compare the resource classes against Xero's published OpenAPI spec"
  task :schema do
    $LOAD_PATH.unshift File.expand_path("lib", __dir__)
    require "xero_kiwi"

    puts "Fields Xero documents that we do not read"
    puts "-" * 70
    Schema.unmodelled.each do |klass, keys|
      puts "\n  #{Coverage.short(klass)}"
      keys.each { |key| puts "    #{key}" }
    end

    puts "\n\nKeys we read that Xero does not document"
    puts "-" * 70
    puts "  Either the spec omits the field or we invented the key. Only a"
    puts "  payload can say which — check `rake xero:coverage` for one."
    Schema.undocumented.each do |klass, keys|
      puts "\n  #{Coverage.short(klass)}"
      keys.each { |key| puts "    #{key}" }
    end

    unmatched = Schema.unmatched
    unless unmatched.empty?
      puts "\n\nClasses with no matching schema in the spec"
      puts "-" * 70
      unmatched.each { |klass| puts "    #{Coverage.short(klass)}" }
    end
    puts
  end
end

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

    unlinked = Llms.unlinked_from_readme
    unless unlinked.empty?
      warn "✗ These docs are in the manifest but not linked from the README's documentation table:"
      unlinked.each { |path| warn "    #{path}" }
      warn "  Add a row for each, or remove them from Llms::DOCS."
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
