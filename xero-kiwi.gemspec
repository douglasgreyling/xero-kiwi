# frozen_string_literal: true

require_relative "lib/xero_kiwi/version"

Gem::Specification.new do |spec|
  spec.name    = "xero-kiwi"
  spec.version = XeroKiwi::VERSION
  spec.authors = ["Douglas Greyling"]
  spec.email   = ["greyling.douglas@gmail.com"]

  spec.summary                           = "A Ruby wrapper for the Xero Accounting API."
  spec.description                       = "XeroKiwi handles the unglamorous parts of integrating with Xero — " \
                                           "OAuth2 with PKCE, automatic token refresh, rate-limit-aware retries, " \
                                           "and typed value objects for accounting resources — so your code can " \
                                           "focus on the business problem rather than the plumbing."
  spec.homepage                          = "https://github.com/douglasgreyling/xero-kiwi"
  spec.license                           = "MIT"
  spec.required_ruby_version             = ">= 3.4.1"
  spec.metadata["allowed_push_host"]     = "https://rubygems.org"
  spec.metadata["homepage_uri"]          = spec.homepage
  spec.metadata["source_code_uri"]       = "https://github.com/douglasgreyling/xero-kiwi"
  spec.metadata["changelog_uri"]         = "https://github.com/douglasgreyling/xero-kiwi/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"]       = "https://github.com/douglasgreyling/xero-kiwi/issues"
  spec.metadata["documentation_uri"]     = "https://github.com/douglasgreyling/xero-kiwi/blob/main/README.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec            = File.basename(__FILE__)
  spec.files         = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore .rspec spec/ .github/ .rubocop.yml])
    end
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "base64", "~> 0.2"
  spec.add_dependency "faraday", "~> 2.0"
  spec.add_dependency "faraday-retry", "~> 2.0"
  spec.add_dependency "jwt", "~> 2.7"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
