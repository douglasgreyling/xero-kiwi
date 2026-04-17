# frozen_string_literal: true

RSpec.describe XeroKiwi::Accounting::Resource do
  let(:nested_klass) do
    Class.new do
      include XeroKiwi::Accounting::Resource

      attribute :name, xero: "Name"
    end
  end

  let(:resource_klass) do
    nested = nested_klass

    Class.new do
      include XeroKiwi::Accounting::Resource

      payload_key "Widgets"

      attribute :widget_id, xero: "WidgetID",   type: :guid
      attribute :name,      xero: "Name",       type: :string
      attribute :count,     xero: "Count",      type: :decimal
      attribute :active,    xero: "Active",     type: :bool
      attribute :created,   xero: "Created",    type: :date
      attribute :parent,    xero: "Parent",     type: :object,     of: nested
      attribute :children,  xero: "Children",   type: :collection, of: nested
    end
  end

  describe ".attribute" do
    it "defines a reader for each declared attribute" do
      instance = resource_klass.new({ "WidgetID" => "abc" })

      expect(instance).to respond_to(:widget_id, :name, :count, :active, :created, :parent, :children)
      expect(instance.widget_id).to eq("abc")
    end

    it "records the declaration on the class" do
      expect(resource_klass.attributes.keys).to eq(%i[widget_id name count active created parent children])
      expect(resource_klass.attributes[:widget_id]).to include(xero: "WidgetID", type: :guid)
    end
  end

  describe "#initialize" do
    it "hydrates every declared attribute via Hydrator" do
      instance = resource_klass.new({
        "WidgetID" => "abc",
        "Name"     => "Widget",
        "Count"    => 42,
        "Active"   => true,
        "Created"  => "2024-03-01T12:00:00Z",
        "Parent"   => { "Name" => "Root" },
        "Children" => [{ "Name" => "A" }, { "Name" => "B" }]
      })

      expect(instance).to have_attributes(
        widget_id: "abc",
        name:      "Widget",
        count:     42,
        active:    true
      )
      expect(instance.created).to be_a(Time)
      expect(instance.parent.name).to eq("Root")
      expect(instance.children.map(&:name)).to eq(%w[A B])
    end

    it "accepts symbol-keyed attrs" do
      instance = resource_klass.new({ WidgetID: "abc", Name: "w" })

      expect(instance.widget_id).to eq("abc")
      expect(instance.name).to eq("w")
    end

    it "defaults missing attributes to nil (or [] for collections)" do
      instance = resource_klass.new({})

      expect(instance.widget_id).to be_nil
      expect(instance.parent).to be_nil
      expect(instance.children).to eq([])
    end

    it "tracks the reference flag" do
      full = resource_klass.new({ "WidgetID" => "abc" })
      ref  = resource_klass.new({ "WidgetID" => "abc" }, { reference: true })

      expect(full.reference?).to be false
      expect(ref.reference?).to be true
    end
  end

  describe "#to_h" do
    it "returns a hash keyed by attribute names" do
      instance = resource_klass.new({ "WidgetID" => "abc", "Name" => "w" })
      hash     = instance.to_h

      expect(hash.keys).to eq(%i[widget_id name count active created parent children])
      expect(hash[:widget_id]).to eq("abc")
      expect(hash[:name]).to eq("w")
    end
  end

  describe "equality" do
    context "with identity declared" do
      let(:klass) do
        Class.new do
          include XeroKiwi::Accounting::Resource
          identity :widget_id
          attribute :widget_id, xero: "WidgetID"
          attribute :name,      xero: "Name"
        end
      end

      it "compares only by the identity attribute" do
        a = klass.new({ "WidgetID" => "abc", "Name" => "X" })
        b = klass.new({ "WidgetID" => "abc", "Name" => "Y" })
        c = klass.new({ "WidgetID" => "xyz", "Name" => "X" })

        expect(a).to eq(b)
        expect(a).to eql(b)
        expect(a.hash).to eq(b.hash)
        expect(a).not_to eq(c)
      end

      it "returns false against a different class" do
        other = Class.new { include XeroKiwi::Accounting::Resource }.new({})
        instance = klass.new({ "WidgetID" => "abc" })

        expect(instance).not_to eq(other)
      end
    end

    context "without identity declared" do
      let(:klass) do
        Class.new do
          include XeroKiwi::Accounting::Resource
          attribute :name, xero: "Name"
          attribute :kind, xero: "Kind"
        end
      end

      it "compares structurally via to_h" do
        a = klass.new({ "Name" => "X", "Kind" => "K" })
        b = klass.new({ "Name" => "X", "Kind" => "K" })
        c = klass.new({ "Name" => "X", "Kind" => "K2" })

        expect(a).to eq(b)
        expect(a.hash).to eq(b.hash)
        expect(a).not_to eq(c)
      end
    end
  end

  describe "#inspect" do
    it "shows every attribute inline in AR style" do
      instance = resource_klass.new({
        "WidgetID" => "abc",
        "Name"     => "Widget",
        "Count"    => 42
      })

      output = instance.inspect

      expect(output).to start_with("#<")
      expect(output).to include("widget_id=\"abc\"")
      expect(output).to include("name=\"Widget\"")
      expect(output).to include("count=42")
    end

    it "collapses collections to a count summary" do
      instance = resource_klass.new({
        "WidgetID" => "abc",
        "Children" => [{ "Name" => "A" }, { "Name" => "B" }, { "Name" => "C" }]
      })

      expect(instance.inspect).to include("children=[3 items]")
    end

    it "collapses nested objects to a one-line reference" do
      instance = resource_klass.new({
        "WidgetID" => "abc",
        "Parent"   => { "Name" => "Root" }
      })

      expect(instance.inspect).to include("parent=#<")
      expect(instance.inspect).not_to include("Root")
    end

    it "shows nil nested objects explicitly" do
      instance = resource_klass.new({ "WidgetID" => "abc" })

      expect(instance.inspect).to include("parent=nil")
    end
  end

  describe ".from_response" do
    it "builds an array of instances from the payload envelope" do
      payload = { "Widgets" => [{ "WidgetID" => "a" }, { "WidgetID" => "b" }] }

      results = resource_klass.from_response(payload)

      expect(results.map(&:widget_id)).to eq(%w[a b])
    end

    it "returns [] for nil payload" do
      expect(resource_klass.from_response(nil)).to eq([])
    end

    it "returns [] when the envelope key is absent" do
      expect(resource_klass.from_response({ "Other" => [] })).to eq([])
    end
  end
end
