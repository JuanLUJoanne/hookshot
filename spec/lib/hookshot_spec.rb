# frozen_string_literal: true

require "rails_helper"

RSpec.describe Hookshot do
  after { described_class.reset_configuration! }

  describe ".configure" do
    it "yields the configuration object" do
      described_class.configure { |c| c.max_retries = 3 }
      expect(described_class.configuration.max_retries).to eq(3)
    end

    it "is idempotent — multiple blocks compose" do
      described_class.configure { |c| c.max_retries = 3 }
      described_class.configure { |c| c.queue_name = :default }
      expect(described_class.configuration.max_retries).to eq(3)
      expect(described_class.configuration.queue_name).to eq(:default)
    end
  end

  describe ".reset_configuration!" do
    it "restores all values to their defaults" do
      described_class.configure { |c| c.max_retries = 1 }
      described_class.reset_configuration!
      expect(described_class.configuration.max_retries).to eq(8)
    end
  end

  describe ".configuration" do
    it "returns the same singleton object across calls" do
      first_call = described_class.configuration
      expect(described_class.configuration).to be(first_call)
    end
  end
end
