# frozen_string_literal: true

require "rails_helper"

RSpec.describe Hookshot::Endpoint do
  subject(:endpoint) { build(:hookshot_endpoint) }

  # ── Associations ────────────────────────────────────────────────────────────

  describe "associations" do
    it { is_expected.to have_many(:subscriptions).dependent(:destroy) }
    it { is_expected.to have_many(:deliveries).dependent(:destroy) }
    it { is_expected.to have_many(:dead_letters).dependent(:destroy) }
  end

  # ── Validations ─────────────────────────────────────────────────────────────

  describe "validations" do
    it { is_expected.to validate_presence_of(:url) }
    it { is_expected.to validate_uniqueness_of(:url) }

    context "with a valid HTTPS URL" do
      it "is valid" do
        endpoint.url = "https://hooks.example.com/receive"
        expect(endpoint).to be_valid
      end
    end

    context "with a valid HTTP URL" do
      it "is valid" do
        endpoint.url = "http://localhost:3001/webhooks"
        expect(endpoint).to be_valid
      end
    end

    context "with a URL that includes a path and query string" do
      it "is valid" do
        endpoint.url = "https://example.com/path/to/hook?token=abc123"
        expect(endpoint).to be_valid
      end
    end

    context "with a non-HTTP scheme" do
      it "is invalid" do
        endpoint.url = "ftp://example.com/hooks"
        expect(endpoint).not_to be_valid
        expect(endpoint.errors[:url]).to include("must be a valid HTTP or HTTPS URL")
      end
    end

    context "with a plain string that is not a URL" do
      it "is invalid" do
        endpoint.url = "not-a-url"
        expect(endpoint).not_to be_valid
      end
    end

    context "with a negative consecutive_failures value" do
      it "is invalid" do
        endpoint.consecutive_failures = -1
        expect(endpoint).not_to be_valid
      end
    end
  end

  # ── Enum ────────────────────────────────────────────────────────────────────

  describe "status enum" do
    it "defaults to active" do
      expect(endpoint).to be_status_active
    end

    it "transitions to paused" do
      endpoint.save!
      endpoint.status_paused!
      expect(endpoint.reload).to be_status_paused
    end

    it "transitions to circuit_open" do
      endpoint.save!
      endpoint.status_circuit_open!
      expect(endpoint.reload).to be_status_circuit_open
    end

    it "provides status-prefixed scopes" do
      active  = create(:hookshot_endpoint)
      paused  = create(:hookshot_endpoint, :paused)

      expect(described_class.status_active).to include(active)
      expect(described_class.status_active).not_to include(paused)
    end
  end

  # ── Callbacks ───────────────────────────────────────────────────────────────

  describe "secret auto-generation" do
    context "when secret is not provided" do
      it "generates a 64-character hex secret on create" do
        endpoint.secret = nil
        endpoint.save!
        expect(endpoint.secret).to match(/\A[0-9a-f]{64}\z/)
      end
    end

    context "when secret is provided" do
      it "preserves the given secret" do
        endpoint.secret = "custom-secret-value"
        endpoint.save!
        expect(endpoint.secret).to eq("custom-secret-value")
      end
    end
  end

  # ── accepts_nested_attributes_for ───────────────────────────────────────────

  describe "nested subscription creation" do
    it "creates subscriptions via nested attributes" do
      endpoint = create(
        :hookshot_endpoint,
        subscriptions_attributes: [
          { event_type: "order.created" },
          { event_type: "order.cancelled" },
        ],
      )
      expect(endpoint.subscriptions.map(&:event_type)).to contain_exactly(
        "order.created",
        "order.cancelled",
      )
    end
  end
end
