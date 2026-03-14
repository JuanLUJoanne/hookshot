# frozen_string_literal: true

require "rails_helper"

RSpec.describe Hookshot::Configuration do
  subject(:config) { described_class.new }

  # ── Defaults ────────────────────────────────────────────────────────────────

  describe "default values" do
    it "sets max_retries to 8" do
      expect(config.max_retries).to eq(8)
    end

    it "sets retry_base_delay to 15 seconds" do
      expect(config.retry_base_delay).to eq(15)
    end

    it "sets retry_max_delay to 3600 seconds (1 hour)" do
      expect(config.retry_max_delay).to eq(3_600)
    end

    it "sets jitter_max to 5 seconds" do
      expect(config.jitter_max).to eq(5)
    end

    it "sets signature_algorithm to :sha256" do
      expect(config.signature_algorithm).to eq(:sha256)
    end

    it "sets queue_name to :webhooks" do
      expect(config.queue_name).to eq(:webhooks)
    end

    it "sets connect_timeout to 5 seconds" do
      expect(config.connect_timeout).to eq(5)
    end

    it "sets read_timeout to 10 seconds" do
      expect(config.read_timeout).to eq(10)
    end
  end

  # ── Overrides ───────────────────────────────────────────────────────────────

  describe "overriding values" do
    it "allows changing max_retries" do
      config.max_retries = 3
      expect(config.max_retries).to eq(3)
    end

    it "allows changing queue_name" do
      config.queue_name = :default
      expect(config.queue_name).to eq(:default)
    end

    it "allows changing retry_base_delay" do
      config.retry_base_delay = 30
      expect(config.retry_base_delay).to eq(30)
    end
  end
end
