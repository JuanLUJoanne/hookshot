# frozen_string_literal: true

require "rails_helper"

RSpec.describe Hookshot::Subscription do
  subject(:subscription) { build(:hookshot_subscription) }

  # ── Associations ────────────────────────────────────────────────────────────

  describe "associations" do
    it { is_expected.to belong_to(:endpoint) }
  end

  # ── Validations ─────────────────────────────────────────────────────────────

  describe "validations" do
    it { is_expected.to validate_presence_of(:event_type) }

    context "with a valid dot-separated event type" do
      it "is valid" do
        subscription.event_type = "order.line_item.created"
        expect(subscription).to be_valid
      end
    end

    context "with a single-word event type" do
      it "is valid" do
        subscription.event_type = "ping"
        expect(subscription).to be_valid
      end
    end

    context "with uppercase letters in event type" do
      it "is invalid" do
        subscription.event_type = "Order.Created"
        expect(subscription).not_to be_valid
        expect(subscription.errors[:event_type]).to be_present
      end
    end

    context "with spaces in event type" do
      it "is invalid" do
        subscription.event_type = "order created"
        expect(subscription).not_to be_valid
      end
    end

    context "with a leading dot in event type" do
      it "is invalid" do
        subscription.event_type = ".order.created"
        expect(subscription).not_to be_valid
      end
    end

    context "when the same event type is registered twice for one endpoint" do
      it "is invalid on the second" do
        endpoint = create(:hookshot_endpoint)
        create(:hookshot_subscription, endpoint: endpoint, event_type: "order.created")
        duplicate = build(:hookshot_subscription, endpoint: endpoint, event_type: "order.created")
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:event_type]).to be_present
      end
    end

    context "when the same event type is registered for two different endpoints" do
      it "is valid for both" do
        create(:hookshot_subscription, event_type: "order.created")
        subscription.event_type = "order.created"
        expect(subscription).to be_valid
      end
    end
  end
end
