# frozen_string_literal: true

require "rails_helper"

RSpec.describe Hookshot::DeadLetter do
  subject(:dead_letter) { build(:hookshot_dead_letter) }

  # ── Associations ────────────────────────────────────────────────────────────

  describe "associations" do
    it { is_expected.to belong_to(:delivery) }
    it { is_expected.to belong_to(:event) }
    it { is_expected.to belong_to(:endpoint) }
  end

  # ── Validations ─────────────────────────────────────────────────────────────

  describe "validations" do
    it { is_expected.to validate_presence_of(:reason) }

    context "with total_attempts of zero" do
      it "is invalid" do
        dead_letter.total_attempts = 0
        expect(dead_letter).not_to be_valid
        expect(dead_letter.errors[:total_attempts]).to be_present
      end
    end

    context "with nil total_attempts" do
      it "is valid" do
        dead_letter.total_attempts = nil
        expect(dead_letter).to be_valid
      end
    end
  end

  # ── Enum ────────────────────────────────────────────────────────────────────

  describe "reason enum" do
    it "defaults to max_retries_exceeded" do
      expect(dead_letter).to be_reason_max_retries_exceeded
    end

    it "supports circuit_open reason" do
      dead_letter.reason = :circuit_open
      expect(dead_letter).to be_reason_circuit_open
    end

    it "supports manual reason" do
      dead_letter.reason = :manual
      expect(dead_letter).to be_reason_manual
    end
  end

  # ── Factory ─────────────────────────────────────────────────────────────────

  describe "factory" do
    it "derives event and endpoint from delivery" do
      dl = create(:hookshot_dead_letter)
      expect(dl.event).to eq(dl.delivery.event)
      expect(dl.endpoint).to eq(dl.delivery.endpoint)
    end
  end
end
