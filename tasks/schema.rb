# frozen_string_literal: true

require "yaml"
require "net/http"
require "uri"
require "fileutils"
require "tmpdir"

# Compares the resource classes against Xero's published OpenAPI spec.
#
# This is the other half of `xero:coverage`. A recording can only show what
# one tenant happened to populate; the spec lists what the endpoint can
# return at all. Neither is sufficient alone, and each has caught what the
# other missed:
#
#   the spec found     LineItem "AccountId", which should be "AccountID".
#                      No recording here carries a line item, so no payload
#                      in this repo could have disproved it
#   the spec missed    User "GlobalUserID", which is absent from the spec
#                      and present on every recorded user. Keying on the
#                      wrong one emptied a consumer's memberships table
#   the spec is wrong  about CreditNote "DueDate", documented but sent on
#                      0 of 18 recorded credit notes
#
# So: treat a difference as a question, not a defect. The payload settles it
# where one exists, and `xero:coverage` is where you look for that.
module Schema
  module_function

  SPEC_URL = "https://raw.githubusercontent.com/XeroAPI/Xero-OpenAPI/master/xero_accounting.yaml"
  CACHE    = File.join(Dir.tmpdir, "xero-kiwi", "xero_accounting.yaml")

  # Our class name => the schema name in Xero's spec, where they differ.
  SCHEMA_NAMES = { "Tracking" => "LineItemTracking" }.freeze

  # Envelope and write-path noise. None of it is part of a read response
  # body, so a difference here says nothing about our modelling.
  IGNORED = %w[
    ValidationErrors Warnings StatusAttributeString Attachments
    UpdatedDateUTCString HasErrors
  ].freeze

  def spec
    @_spec ||= YAML.unsafe_load_file(fetch)["components"]["schemas"]
  end

  def fetch
    return CACHE if File.exist?(CACHE) && File.mtime(CACHE) > Time.now - (24 * 60 * 60)

    FileUtils.mkdir_p(File.dirname(CACHE))
    File.write(CACHE, Net::HTTP.get(URI(SPEC_URL)))
    CACHE
  end

  def accounting = XeroKiwi::Accounting

  def resource_classes
    accounting.constants.sort.map { |name| accounting.const_get(name) }
              .select { |const| const.is_a?(Class) && const.respond_to?(:attributes) }
  end

  def schema_name(klass)
    short = klass.name.split("::").last
    SCHEMA_NAMES.fetch(short, short)
  end

  def properties(klass)
    spec.dig(schema_name(klass), "properties")&.keys
  end

  def our_keys(klass)
    klass.attributes.values.flat_map { |attribute| klass.xero_keys(attribute) }
  end

  # Fields Xero documents that we never read.
  def unmodelled
    resource_classes.each_with_object({}) do |klass, found|
      documented   = properties(klass) or next
      missing      = documented - our_keys(klass) - IGNORED
      found[klass] = missing unless missing.empty?
    end
  end

  # Keys we read that Xero does not document — each one either a field the
  # spec omits or a key we invented, and only a payload can say which.
  def undocumented
    resource_classes.each_with_object({}) do |klass, found|
      documented   = properties(klass) or next
      extra        = our_keys(klass) - documented
      found[klass] = extra unless extra.empty?
    end
  end

  def unmatched
    resource_classes.reject { |klass| properties(klass) }
  end
end
