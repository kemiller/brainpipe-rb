RSpec.describe Brainpipe::Namespace do
  describe "#initialize" do
    it "creates namespace from hash" do
      ns = described_class.new(name: "test", count: 42)
      expect(ns[:name]).to eq("test")
      expect(ns[:count]).to eq(42)
    end

    it "converts string keys to symbols" do
      ns = described_class.new("name" => "test")
      expect(ns[:name]).to eq("test")
    end

    it "is frozen after creation" do
      ns = described_class.new(name: "test")
      expect(ns).to be_frozen
    end
  end

  describe "#[]" do
    let(:ns) { described_class.new(name: "test", count: 42) }

    it "returns value for symbol key" do
      expect(ns[:name]).to eq("test")
    end

    it "returns value for string key" do
      expect(ns["name"]).to eq("test")
    end

    it "returns nil for missing key" do
      expect(ns[:missing]).to be_nil
    end
  end

  describe "#merge" do
    let(:original) { described_class.new(name: "test", count: 42) }

    it "returns new namespace with merged properties" do
      merged = original.merge(status: "active")
      expect(merged[:name]).to eq("test")
      expect(merged[:count]).to eq(42)
      expect(merged[:status]).to eq("active")
    end

    it "does not modify original namespace" do
      original.merge(status: "active")
      expect(original.keys).to eq([:name, :count])
    end

    it "overwrites existing keys" do
      merged = original.merge(name: "updated")
      expect(merged[:name]).to eq("updated")
      expect(original[:name]).to eq("test")
    end

    it "accepts string keys" do
      merged = original.merge("status" => "active")
      expect(merged[:status]).to eq("active")
    end
  end

  describe "#delete" do
    let(:original) { described_class.new(name: "test", count: 42, status: "active") }

    it "returns new namespace without specified keys" do
      deleted = original.delete(:count)
      expect(deleted.keys).to eq([:name, :status])
    end

    it "does not modify original namespace" do
      original.delete(:count)
      expect(original.keys).to eq([:name, :count, :status])
    end

    it "handles multiple keys" do
      deleted = original.delete(:count, :status)
      expect(deleted.keys).to eq([:name])
    end

    it "handles missing keys gracefully" do
      deleted = original.delete(:missing)
      expect(deleted.keys).to eq([:name, :count, :status])
    end

    it "accepts string keys" do
      deleted = original.delete("count")
      expect(deleted.keys).to eq([:name, :status])
    end
  end

  describe "#to_h" do
    let(:ns) { described_class.new(name: "test", count: 42) }

    it "returns hash representation" do
      expect(ns.to_h).to eq({ name: "test", count: 42 })
    end

    it "returns a copy that can be modified" do
      hash = ns.to_h
      hash[:new_key] = "value"
      expect(ns.key?(:new_key)).to be false
    end
  end

  describe "#keys" do
    it "returns property names" do
      ns = described_class.new(name: "test", count: 42)
      expect(ns.keys).to eq([:name, :count])
    end
  end

  describe "#key?" do
    let(:ns) { described_class.new(name: "test") }

    it "returns true for existing key" do
      expect(ns.key?(:name)).to be true
    end

    it "returns false for missing key" do
      expect(ns.key?(:missing)).to be false
    end

    it "accepts string keys" do
      expect(ns.key?("name")).to be true
    end
  end

  describe "equality" do
    it "considers namespaces with same data equal" do
      ns1 = described_class.new(name: "test")
      ns2 = described_class.new(name: "test")
      expect(ns1).to eq(ns2)
    end

    it "considers namespaces with different data unequal" do
      ns1 = described_class.new(name: "test")
      ns2 = described_class.new(name: "other")
      expect(ns1).not_to eq(ns2)
    end

    it "is not equal to non-namespace objects" do
      ns = described_class.new(name: "test")
      expect(ns).not_to eq({ name: "test" })
    end
  end

  describe "immutability" do
    it "prevents modification of internal data" do
      ns = described_class.new(name: "test")
      expect { ns.to_h[:name] = "modified" }.not_to change { ns[:name] }
    end

    it "freezes the namespace object" do
      ns = described_class.new(name: "test")
      expect(ns).to be_frozen
    end
  end
end
