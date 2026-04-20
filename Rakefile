# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

require "rubocop/rake_task"

RuboCop::RakeTask.new

# Files included in llms-full.txt, in reading order. Keep README first, then
# the docs in the same order the README's table of contents lists them.
LLMS_SOURCE_FILES = %w[
  README.md
  docs/getting-started.md
  docs/client.md
  docs/oauth.md
  docs/tokens.md
  docs/connections.md
  docs/accounting/contact.md
  docs/accounting/contact-group.md
  docs/accounting/organisation.md
  docs/accounting/user.md
  docs/accounting/credit-note.md
  docs/accounting/invoice.md
  docs/accounting/payment.md
  docs/accounting/overpayment.md
  docs/accounting/prepayment.md
  docs/accounting/branding-theme.md
  docs/accounting/address.md
  docs/accounting/phone.md
  docs/accounting/external-link.md
  docs/accounting/payment-terms.md
  docs/errors.md
  docs/retries-and-rate-limits.md
  docs/querying.md
].freeze

LLMS_FULL_PATH = "llms-full.txt"

# Builds the llms-full.txt content from LLMS_SOURCE_FILES. Pure function:
# returns a String, doesn't touch the filesystem. Both `llms:build` and
# `llms:check` use this so the two tasks can never disagree about the
# expected output.
def build_llms_full
  out = String.new(encoding: "UTF-8")
  out << "# Xero Kiwi — full documentation\n\n"
  out << "This file is the complete documentation for the Xero Kiwi gem (a Ruby wrapper for the Xero Accounting API), assembled into a single document for LLM consumption. It contains the README and every doc in the docs/ folder, in reading order.\n\n"
  out << "For the curated index version, see llms.txt in the same directory.\n\n"
  out << "Source: https://github.com/douglasgreyling/xero-kiwi\n\n"
  LLMS_SOURCE_FILES.each { |path| append_file_block(out, path) }
  out
end

def append_file_block(out, path)
  separator = "=" * 80
  out << "\n" << separator << "\n"
  out << "FILE: #{path}\n"
  out << separator << "\n\n"
  out << File.read(path, encoding: "UTF-8") << "\n"
end

namespace :llms do
  desc "Regenerate llms-full.txt from README and docs/"
  task :build do
    File.write(LLMS_FULL_PATH, build_llms_full)
    puts "Wrote #{LLMS_FULL_PATH} (#{File.size(LLMS_FULL_PATH)} bytes, #{LLMS_SOURCE_FILES.size} source files)"
  end

  desc "Verify llms-full.txt is up to date with README and docs/"
  task :check do
    expected = build_llms_full
    actual   = File.exist?(LLMS_FULL_PATH) ? File.read(LLMS_FULL_PATH, encoding: "UTF-8") : ""

    if expected == actual
      puts "✓ #{LLMS_FULL_PATH} is up to date"
    else
      warn "✗ #{LLMS_FULL_PATH} is out of date with README/docs."
      warn "  Run `bundle exec rake llms:build` and commit the result."
      exit 1
    end
  end
end

# Top-level convenience alias.
desc "Regenerate llms-full.txt (alias for llms:build)"
task llms: "llms:build"

task default: %i[spec rubocop llms:check]
