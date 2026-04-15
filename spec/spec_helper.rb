# frozen_string_literal: true

require "dotenv/load"
require "xero_kiwi"
require "webmock/rspec"
require "vcr"

Dir[File.expand_path("support/**/*.rb", __dir__)].each { |f| require f }

WebMock.disable_net_connect!(allow_localhost: true)

# Deterministic placeholders we replace sensitive data with before writing the
# cassette to disk. Tests assert against these values, so anything that gets
# recorded against the live Xero API ends up looking the same on disk.
SANITISED_FIELDS = {
  "id"                           => "00000000-0000-0000-0000-000000000001",
  "authEventId"                  => "11111111-1111-1111-1111-000000000001",
  "tenantId"                     => "22222222-2222-2222-2222-000000000001",
  "tenantName"                   => "Sanitised Tenant",
  "OrganisationID"               => "33333333-3333-3333-3333-000000000001",
  "Name"                         => "Sanitised Organisation",
  "LegalName"                    => "Sanitised Organisation Limited",
  "TaxNumber"                    => "000-000-000",
  "RegistrationNumber"           => "0000000",
  "EmployerIdentificationNumber" => "000-00-0000",
  "UserID"                       => "44444444-4444-4444-4444-000000000001",
  "EmailAddress"                 => "sanitised@example.com"
}.freeze

VCR.configure do |config|
  config.cassette_library_dir     = "spec/fixtures/vcr_cassettes"
  config.default_cassette_options = { record: :once }
  config.hook_into :webmock
  config.configure_rspec_metadata!

  # Scrub the bearer token. Sourced from ENV at record time, replaced with a
  # placeholder both in the cassette and at replay time so the test setup
  # doesn't need a real token to run.
  config.filter_sensitive_data("<XERO_ACCESS_TOKEN>") do
    ENV.fetch("XERO_ACCESS_TOKEN", nil)
  end

  # Scrub the tenant ID from request headers so it doesn't leak into cassettes.
  config.filter_sensitive_data("<XERO_TENANT_ID>") do
    ENV.fetch("XERO_TENANT_ID", nil)
  end

  # Sanitise the response body before VCR persists it. Anything Xero returns
  # that could identify the tenant gets replaced with a deterministic
  # placeholder, so the cassette is safe to commit.
  config.before_record do |interaction|
    body = interaction.response.body
    next if body.nil? || body.empty?

    begin
      parsed = JSON.parse(body)
    rescue JSON::ParserError
      next
    end

    sanitised                 = sanitise_xero_payload(parsed)
    interaction.response.body = JSON.dump(sanitised)
  end
end

def sanitise_xero_payload(node)
  case node
  when Array then node.map { |item| sanitise_xero_payload(item) }
  when Hash  then sanitise_xero_hash(node)
  else node
  end
end

def sanitise_xero_hash(hash)
  hash.each_with_object({}) do |(key, value), acc|
    acc[key] = SANITISED_FIELDS.fetch(key) { sanitise_xero_payload(value) }
  end
end

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
