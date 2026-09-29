# frozen_string_literal: true

require "yaml"
require "json"
require "bigdecimal"

# Compares every recorded Xero response in spec/fixtures/vcr_cassettes
# against the resource classes that model it, on the three axes that have
# each produced a silent bug in this gem:
#
#   unmodelled  - Xero sends a key and nothing reads it. Found the
#                 AppliedAmount on invoice-nested allocation stubs, where
#                 the nearest-looking reader returned a different number.
#   unpopulated - an attribute that is nil in every recording. Usually
#                 benign (list endpoints omit LineItems), but a wrong
#                 `xero:` key looks exactly like this. It is the shape of
#                 the 0.6.0 Allocation regression.
#   mistyped    - the declared `type:` disagrees with what Xero sends.
#
# Reports rather than fails. A gate here would need an allowlist of the
# legitimately-absent keys, and an allowlist rots into a list nobody reads —
# which is the failure this whole exercise exists to avoid. Run it when
# adding or changing a resource, and read the output.
module Coverage
  module_function

  CASSETTES = "spec/fixtures/vcr_cassettes/**/*.yml"

  # Organisation declares no payload_key; it overrides from_response with
  # the envelope hardcoded, so it is invisible to the lookup below.
  EXTRA_PAYLOAD_KEYS = { "Organisations" => "Organisation" }.freeze

  EXPECTED_CLASSES = {
    string: %w[String], enum: %w[String], guid: %w[String],
    bool: %w[TrueClass FalseClass], decimal: %w[Float Integer String],
    date: %w[String]
  }.freeze

  def accounting = XeroKiwi::Accounting

  def resource_classes
    accounting.constants.map { |name| accounting.const_get(name) }
              .select { |const| const.is_a?(Class) && const.respond_to?(:attributes) }
  end

  def by_payload_key
    extra = EXTRA_PAYLOAD_KEYS.transform_values { |name| accounting.const_get(name) }

    resource_classes.select { |klass| klass.respond_to?(:payload_key) && klass.payload_key }
                    .to_h { |klass| [klass.payload_key, klass] }
                    .merge(extra)
  end

  def recorded_payloads
    Dir[CASSETTES].flat_map do |path|
      YAML.unsafe_load_file(path)["http_interactions"].to_a.filter_map do |interaction|
        body = interaction.dig("response", "body", "string")
        parse_json(body) if body
      end
    end
  end

  def parse_json(body)
    json = JSON.parse(body)
    json if json.is_a?(Hash)
  rescue JSON::ParserError
    nil
  end

  # Walks a recorded item alongside the class that models it, descending
  # into nested resources via each attribute's `of:`.
  def survey
    report = { unmodelled: nested_hash, present: nested_hash, classes: nested_hash, seen: Hash.new(0) }
    lookup = by_payload_key

    recorded_payloads.each do |payload|
      payload.each do |envelope, items|
        klass = lookup[envelope] or next

        Array(items).each { |item| visit(klass, item, report) }
      end
    end

    report
  end

  def nested_hash
    Hash.new { |outer, key| outer[key] = Hash.new { |inner, name| inner[name] = Hash.new(0) } }
  end

  def visit(klass, item, report)
    return unless item.is_a?(Hash)

    report[:seen][klass] += 1
    record_unmodelled(klass, item, report)

    klass.attributes.each do |name, spec|
      raw = klass.raw_value(item, spec)
      record_attribute(klass, name, spec, raw, report)
      descend(spec, raw, report)
    end
  end

  def record_unmodelled(klass, item, report)
    modelled = klass.attributes.values.flat_map { |spec| klass.xero_keys(spec) }

    (item.keys - modelled).each do |key|
      report[:unmodelled][klass][key][blank?(item[key]) ? :blank : :populated] += 1
    end
  end

  def record_attribute(klass, name, spec, raw, report)
    report[:present][klass][name][blank?(raw) ? :blank : :populated] += 1
    return if raw.nil? || %i[object collection].include?(spec[:type])

    report[:classes][klass][name][raw.class.name] += 1
  end

  def descend(spec, raw, report)
    klass = child_class(spec) or return

    case spec[:type]
    when :object     then visit(klass, raw, report)
    when :collection then Array(raw).each { |child| visit(klass, child, report) }
    end
  end

  def child_class(spec)
    target = spec[:of] or return nil

    target.is_a?(Class) ? target : accounting::Hydrator.resolve_class(target)
  rescue NameError
    nil
  end

  def blank?(value)
    value.nil? || value == "" || value == [] || value == {}
  end

  def short(klass) = klass.name.split("::").last

  def with_findings(source)
    source.each_with_object({}) do |(klass, values), found|
      rows         = yield(values, klass)
      found[klass] = rows unless rows.empty?
    end
  end

  # Keys Xero sends that no attribute reads.
  def unmodelled(report)
    with_findings(report[:unmodelled]) do |keys|
      keys.map { |key, counts| [key, counts[:populated], counts[:populated] + counts[:blank]] }
          .sort_by { |_, populated, _| -populated }
    end
  end

  # Attributes that were nil in every recording.
  def unpopulated(report)
    with_findings(report[:present]) do |attrs|
      attrs.reject { |_, counts| counts[:populated].positive? }.keys
    end
  end

  # Attributes whose recorded value disagrees with the declared type.
  def mistyped(report)
    with_findings(report[:classes]) do |attrs, klass|
      attrs.filter_map { |name, counts| mistyped_row(klass, name, counts) }
    end
  end

  def mistyped_row(klass, name, counts)
    spec = klass.attributes[name]
    return if spec[:hydrate] # a custom lambda bypasses the declared type

    expected = EXPECTED_CLASSES[spec[:type]]
    return if expected.nil? || (counts.keys - expected).empty?

    [name, spec[:type], counts]
  end

  # Classes no recording exercises at all.
  def unexercised(report)
    resource_classes.reject { |klass| report[:seen].key?(klass) }
  end
end
