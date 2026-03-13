# frozen_string_literal: true

require "rails_helper"

RSpec.describe Hookshot::Delivery do
  subject(:delivery) { build(:hookshot_delivery) }

  # ── Associations ────────────────────────────────────────────────────────────

  describe "associations" do
    it { is_expected.to belong_to(:event) }
    it { is_expected.to belong_to(:endpoint) }
    it { is_expected.to have_one(:dead_letter).dependent(:destroy) }
  end

  # ── Validations ─────────────────────────────────────────────────────────────

  describe "validations" do
    it { is_expected.to validate_uniqueness_of(:idempotency_key) }

    context "with attempt_number of zero" do
      it "is invalid" do
        delivery.attempt_number = 0
        expect(delivery).not_to be_valid
        expect(delivery.errors[:attempt_number]).to be_present
      end
    end

    context "with a negative attempt_number" do
      it "is invalid" do
        delivery.attempt_number = -1
        expect(delivery).not_to be_valid
      end
    end
  end

  # ── Enum ────────────────────────────────────────────────────────────────────

  describe "status enum" do
    it "defaults to pending" do
      expect(delivery).to be_status_pending
    end

    it "transitions to success" do
      delivery.save!
      delivery.status_success!
      expect(delivery.reload).to be_status_success
    end

    it "transitions to failed" do
      delivery.save!
      delivery.status_failed!
      expect(delivery.reload).to be_status_failed
    end

    it "transitions to circuit_open" do
      delivery.save!
      delivery.status_circuit_open!
      expect(delivery.reload).to be_status_circuit_open
    end
  end

  # ── Callbacks ───────────────────────────────────────────────────────────────

  describe "idempotency_key auto-generation" do
    context "when idempotency_key is not provided" do
      it "generates a UUID on create" do
        delivery.idempotency_key = nil
        delivery.save!
        expect(delivery.idempotency_key).to match(
          /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/,
        )
      end
    end

    context "when idempotency_key is provided" do
      it "preserves the given key" do
        key = "explicit-key"
        delivery.idempotency_key = key
        delivery.save!
        expect(delivery.idempotency_key).to eq(key)
      end
    end
  end

  # ── Factory traits ──────────────────────────────────────────────────────────

  describe "factory traits" do
    it "builds a successful delivery with the :success trait" do
      d = build(:hookshot_delivery, :success)
      expect(d).to be_status_success
      expect(d.response_status).to eq(200)
      expect(d.duration_ms).to be_positive
    end

    it "builds a timed-out delivery with the :timed_out trait" do
      d = build(:hookshot_delivery, :timed_out)
      expect(d).to be_status_failed
      expect(d.error_message).to eq("execution expired")
    end
  end
end
