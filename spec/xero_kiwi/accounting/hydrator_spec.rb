# frozen_string_literal: true

RSpec.describe XeroKiwi::Accounting::Hydrator do
  describe ".call" do
    context "with a custom hydrate lambda" do
      it "runs the lambda before the nil guard" do
        spec = { type: :string, hydrate: ->(raw) { raw || "fallback" } }

        expect(described_class.call(nil, spec)).to eq("fallback")
        expect(described_class.call("given", spec)).to eq("given")
      end

      it "ignores :type dispatch when a lambda is present" do
        spec = { type: :date, hydrate: ->(raw) { "custom:#{raw}" } }

        expect(described_class.call("2024-01-01", spec)).to eq("custom:2024-01-01")
      end
    end

    context "with a nil raw value" do
      it "returns an empty array for :collection" do
        expect(described_class.call(nil, { type: :collection, of: String })).to eq([])
      end

      it "returns nil for every other type" do
        %i[string enum guid bool decimal date object].each do |type|
          expect(described_class.call(nil, { type: type, of: String })).to be_nil
        end
      end
    end

    # Xero sends "" for a text field with no value, where its XML
    # representation produced nil. Left as "", it reaches a database column
    # and changes what queries match — a `where.not(logo_url: nil)` starts
    # returning rows with no logo.
    context "with an empty string" do
      it "reads as nil on text types" do
        %i[string enum guid].each do |type|
          expect(described_class.call("", { type: type })).to be_nil
        end
      end

      # Trimming " " would be editorialising on a value rather than
      # recognising an absent one.
      it "leaves whitespace alone" do
        expect(described_class.call(" ", { type: :string })).to eq(" ")
      end

      # Decimals were left alone when text types were normalised, on the
      # grounds that it wanted its own decision. This is that decision: ""
      # means absent here too, and the alternative is a silent zero in a
      # money field.
      it "reads as nil on decimals" do
        expect(described_class.call("", { type: :decimal })).to be_nil
      end

      it "does not disturb ordinary values" do
        expect(described_class.call("Maple Florists", { type: :string })).to eq("Maple Florists")
      end
    end

    context "with pass-through types" do
      it "returns a non-empty raw value unchanged for :string, :enum, :guid" do
        %i[string enum guid].each do |type|
          expect(described_class.call("abc", { type: type })).to eq("abc")
        end

        expect(described_class.call(true, { type: :bool })).to be true
      end
    end

    # Xero sends money as a JSON number. Floats drift under arithmetic even
    # when each value round-trips exactly, which is what makes the failure
    # quiet: every field looks right and only the sum is wrong.
    context "with :decimal" do
      it "converts Xero's JSON numbers to BigDecimal" do
        expect(described_class.call(123.45, { type: :decimal })).to eql(BigDecimal("123.45"))
      end

      it "converts integers too" do
        expect(described_class.call(100, { type: :decimal })).to eql(BigDecimal("100"))
      end

      it "takes the decimal Xero wrote, not the Float approximation of it" do
        expect(described_class.call(19_812.97, { type: :decimal }).to_s("F")).to eq("19812.97")
      end

      it "parses a numeric string" do
        expect(described_class.call("521.23", { type: :decimal })).to eql(BigDecimal("521.23"))
      end

      # String#to_d answers 0.0 here, and a silent zero in a money column is
      # the failure this gem has shipped twice.
      it "reads unparseable input as nil rather than zero" do
        expect(described_class.call("not a number", { type: :decimal })).to be_nil
      end

      it "restores the identity that Floats break" do
        sub_total = described_class.call(17_228.67, { type: :decimal })
        total_tax = described_class.call(2_584.3, { type: :decimal })

        expect(sub_total + total_tax).to eq(described_class.call(19_812.97, { type: :decimal }))
      end
    end

    context "with :date" do
      it "parses Xero's /Date(ms)/ format" do
        time = described_class.call("/Date(1574275974000)/", { type: :date })

        expect(time).to be_a(Time)
        expect(time.utc?).to be true
        expect(time.to_i).to eq(1_574_275_974)
      end

      it "parses ISO 8601 without timezone as UTC" do
        time = described_class.call("2019-07-09T23:40:30", { type: :date })

        expect(time).to be_a(Time)
        expect(time.utc?).to be true
        expect(time.year).to eq(2019)
      end

      it "parses ISO 8601 with Z suffix" do
        time = described_class.call("2024-03-01T12:00:00Z", { type: :date })

        expect(time).to be_a(Time)
        expect(time.utc?).to be true
      end

      it "returns nil for empty strings" do
        expect(described_class.call("", { type: :date })).to be_nil
        expect(described_class.call("   ", { type: :date })).to be_nil
      end

      it "returns nil for unparseable values" do
        expect(described_class.call("not a date", { type: :date })).to be_nil
      end
    end

    context "with :object" do
      it "constructs a new instance of the klass" do
        klass = Class.new do
          attr_reader :value

          def initialize(value) = @value = value
        end

        result = described_class.call("raw", { type: :object, of: klass })

        expect(result).to be_a(klass)
        expect(result.value).to eq("raw")
      end

      it "passes reference: true when the spec sets reference" do
        klass = Class.new do
          attr_reader :value, :ref

          def initialize(value, reference: false)
            @value = value
            @ref   = reference
          end
        end

        result = described_class.call("raw", { type: :object, of: klass, reference: true })

        expect(result.ref).to be true
      end

      it "raises when :of is missing" do
        expect { described_class.call("raw", { type: :object }) }
          .to raise_error(ArgumentError, /requires `of:`/)
      end
    end

    context "with :collection" do
      let(:item_klass) do
        Class.new do
          attr_reader :value

          def initialize(value) = @value = value
        end
      end

      it "maps each item through the klass constructor" do
        result = described_class.call(%w[a b c], { type: :collection, of: item_klass })

        expect(result.map(&:value)).to eq(%w[a b c])
      end

      it "passes reference: true when the spec sets reference" do
        klass = Class.new do
          attr_reader :ref

          def initialize(_value, reference: false) = @ref = reference
        end

        result = described_class.call(%w[a b], { type: :collection, of: klass, reference: true })

        expect(result.map(&:ref)).to eq([true, true])
      end
    end

    context "with an unknown type" do
      it "raises ArgumentError" do
        expect { described_class.call("raw", { type: :wat }) }
          .to raise_error(ArgumentError, /unknown attribute type/)
      end
    end
  end
end
