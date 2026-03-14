# frozen_string_literal: true

require "rails_helper"

RSpec.describe Hookshot::Services::SignatureGenerator do
  let(:secret)  { "test-secret-key" }
  let(:payload) { '{"order_id":42}' }
  let(:timestamp) { 1_710_364_800 }

  describe ".call" do
    subject(:result) { described_class.call(payload:, secret:, timestamp:) }

    it "returns a hash with :signature and :timestamp keys" do
      expect(result).to include(:signature, :timestamp)
    end

    it "returns the timestamp as a string" do
      expect(result[:timestamp]).to eq(timestamp.to_s)
    end

    it "prefixes the signature with the algorithm" do
      expect(result[:signature]).to start_with("sha256=")
    end

    it "produces a 71-character signature (sha256= + 64 hex chars)" do
      expect(result[:signature].length).to eq(71)
    end

    context "with a deterministic input" do
      it "produces the same signature each time" do
        first  = described_class.call(payload:, secret:, timestamp:)
        second = described_class.call(payload:, secret:, timestamp:)
        expect(first[:signature]).to eq(second[:signature])
      end
    end

    context "when timestamp is not provided" do
      it "uses the current Unix time" do
        freeze_time = Time.now.to_i
        allow(Time).to receive(:now).and_return(Time.zone.at(freeze_time))
        result = described_class.call(payload:, secret:)
        expect(result[:timestamp]).to eq(freeze_time.to_s)
      end
    end

    context "when the payload changes" do
      it "produces a different signature" do
        sig1 = described_class.call(payload: '{"a":1}', secret:, timestamp:)[:signature]
        sig2 = described_class.call(payload: '{"a":2}', secret:, timestamp:)[:signature]
        expect(sig1).not_to eq(sig2)
      end
    end

    context "when the secret changes" do
      it "produces a different signature" do
        sig1 = described_class.call(payload:, secret: "secret-a", timestamp:)[:signature]
        sig2 = described_class.call(payload:, secret: "secret-b", timestamp:)[:signature]
        expect(sig1).not_to eq(sig2)
      end
    end

    context "when the timestamp changes" do
      it "produces a different signature" do
        sig1 = described_class.call(payload:, secret:, timestamp: 1_000_000)[:signature]
        sig2 = described_class.call(payload:, secret:, timestamp: 1_000_001)[:signature]
        expect(sig1).not_to eq(sig2)
      end
    end
  end
end
