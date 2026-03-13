# frozen_string_literal: true

require "rails_helper"

RSpec.describe Hookshot::Event do
  subject(:event) { build(:hookshot_event) }

  # ── Associations ────────────────────────────────────────────────────────────

  describe "associations" do
    it { is_expected.to have_many(:deliveries).dependent(:destroy) }
    it { is_expected.to have_many(:dead_letters).dependent(:destroy) }
  end

  # ── Validations ─────────────────────────────────────────────────────────────

  describe "validations" do
    it { is_expected.to validate_presence_of(:event_type) }
    it { is_expected.to validate_uniqueness_of(:idempotency_key) }
  end

  # ── Enum ────────────────────────────────────────────────────────────────────

  describe "status enum" do
    it "defaults to pending" do
      expect(event).to be_status_pending
    end

    it "transitions to dispatched" do
      event.save!
      event.status_dispatched!
      expect(event.reload).to be_status_dispatched
    end

    it "transitions to completed" do
      event.save!
      event.status_completed!
      expect(event.reload).to be_status_completed
    end

    it "transitions to failed" do
      event.save!
      event.status_failed!
      expect(event.reload).to be_status_failed
    end
  end

  # ── Callbacks ───────────────────────────────────────────────────────────────

  describe "idempotency_key auto-generation" do
    context "when idempotency_key is not provided" do
      it "generates a UUID on create" do
        event.idempotency_key = nil
        event.save!
        expect(event.idempotency_key).to match(
          /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/,
        )
      end
    end

    context "when idempotency_key is provided" do
      it "preserves the given key" do
        key = "my-custom-idempotency-key"
        event.idempotency_key = key
        event.save!
        expect(event.idempotency_key).to eq(key)
      end
    end

    context "when the same idempotency_key is used twice" do
      it "raises on the second create" do
        key = SecureRandom.uuid
        create(:hookshot_event, idempotency_key: key)
        duplicate = build(:hookshot_event, idempotency_key: key)
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:idempotency_key]).to be_present
      end
    end
  end
end
