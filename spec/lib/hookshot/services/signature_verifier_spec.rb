# frozen_string_literal: true

require "rails_helper"

RSpec.describe Hookshot::Services::SignatureVerifier do
  let(:secret)    { "verifier-secret" }
  let(:payload)   { '{"event":"order.created"}' }
  let(:timestamp) { Time.now.to_i }
  let(:generated) { Hookshot::Services::SignatureGenerator.call(payload:, secret:, timestamp:) }
  let(:signature) { generated[:signature] }

  describe ".valid?" do
    subject(:valid) do
      described_class.valid?(payload:, signature:, timestamp: timestamp.to_s, secret:)
    end

    # ── Happy path ────────────────────────────────────────────────────────────

    context "with a correct signature and fresh timestamp" do
      it { is_expected.to be(true) }
    end

    # ── Payload tampering ─────────────────────────────────────────────────────

    context "when the payload has been tampered with" do
      it "rejects the request" do
        # Sign the original payload, then verify against a modified body.
        original_sig = Hookshot::Services::SignatureGenerator.call(
          payload: '{"event":"order.created"}',
          secret:,
          timestamp:,
        )[:signature]

        result = described_class.valid?(
          payload: '{"event":"order.created","injected":true}',
          signature: original_sig,
          timestamp: timestamp.to_s,
          secret:,
        )
        expect(result).to be(false)
      end
    end

    context "when the signature is for a different payload" do
      it "is invalid" do
        other_sig = Hookshot::Services::SignatureGenerator.call(
          payload: '{"other":"payload"}',
          secret:,
          timestamp:,
        )[:signature]

        result = described_class.valid?(
          payload:,
          signature: other_sig,
          timestamp: timestamp.to_s,
          secret:,
        )
        expect(result).to be(false)
      end
    end

    # ── Wrong secret ──────────────────────────────────────────────────────────

    context "when the wrong secret is used for verification" do
      it "is invalid" do
        result = described_class.valid?(
          payload:,
          signature:,
          timestamp: timestamp.to_s,
          secret: "wrong-secret",
        )
        expect(result).to be(false)
      end
    end

    # ── Timestamp replay ──────────────────────────────────────────────────────

    context "when the timestamp is older than the replay tolerance" do
      it "is invalid" do
        stale_ts  = Time.now.to_i - (Hookshot::Services::SignatureVerifier::REPLAY_TOLERANCE + 1)
        stale_sig = Hookshot::Services::SignatureGenerator.call(payload:, secret:, timestamp: stale_ts)[:signature]
        result    = described_class.valid?(payload:, signature: stale_sig, timestamp: stale_ts.to_s, secret:)
        expect(result).to be(false)
      end
    end

    context "when the timestamp is exactly at the tolerance boundary" do
      it "is valid" do
        boundary_ts  = Time.now.to_i - Hookshot::Services::SignatureVerifier::REPLAY_TOLERANCE
        boundary_sig = Hookshot::Services::SignatureGenerator.call(payload:, secret:,
                                                                   timestamp: boundary_ts,)[:signature]
        result       = described_class.valid?(payload:, signature: boundary_sig, timestamp: boundary_ts.to_s, secret:)
        expect(result).to be(true)
      end
    end

    # ── Missing / blank headers ───────────────────────────────────────────────

    context "when the signature header is missing" do
      it "is invalid" do
        result = described_class.valid?(payload:, signature: nil, timestamp: timestamp.to_s, secret:)
        expect(result).to be(false)
      end
    end

    context "when the timestamp header is missing" do
      it "is invalid" do
        result = described_class.valid?(payload:, signature:, timestamp: nil, secret:)
        expect(result).to be(false)
      end
    end

    context "when the timestamp header is blank" do
      it "is invalid" do
        result = described_class.valid?(payload:, signature:, timestamp: "", secret:)
        expect(result).to be(false)
      end
    end
  end
end
