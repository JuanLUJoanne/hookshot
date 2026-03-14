# frozen_string_literal: true

require "rails_helper"

RSpec.describe Hookshot::Services::EventDispatcher do
  subject(:dispatch) do
    described_class.call(event_type: "order.created", payload: { order_id: 42 })
  end

  let!(:endpoint) { create(:hookshot_endpoint) }

  before { create(:hookshot_subscription, endpoint:, event_type: "order.created") }

  # ── Happy path ──────────────────────────────────────────────────────────────

  describe ".call" do
    context "when active endpoints are subscribed" do
      it "creates an Event record" do
        expect { dispatch }.to change(Hookshot::Event, :count).by(1)
      end

      it "creates one Delivery per subscribed endpoint" do
        expect { dispatch }.to change(Hookshot::Delivery, :count).by(1)
      end

      it "enqueues one DeliveryJob per subscribed endpoint" do
        expect { dispatch }.to have_enqueued_job(Hookshot::DeliveryJob).exactly(:once)
      end

      it "returns a dispatched Event" do
        event = dispatch
        expect(event).to be_a(Hookshot::Event)
        expect(event).to be_status_dispatched
      end

      it "sets the correct event_type on the event" do
        expect(dispatch.event_type).to eq("order.created")
      end

      it "sets the correct payload on the event" do
        expect(dispatch.payload).to eq({ "order_id" => 42 })
      end
    end

    context "when multiple active endpoints are subscribed" do
      let!(:endpoint2) { create(:hookshot_endpoint) }

      before { create(:hookshot_subscription, endpoint: endpoint2, event_type: "order.created") }

      it "creates one Delivery per endpoint" do
        expect { dispatch }.to change(Hookshot::Delivery, :count).by(2)
      end

      it "enqueues one DeliveryJob per endpoint" do
        expect { dispatch }.to have_enqueued_job(Hookshot::DeliveryJob).exactly(:twice)
      end
    end

    # ── Idempotency ─────────────────────────────────────────────────────────

    context "when the idempotency_key has already been used" do
      let(:key) { SecureRandom.uuid }

      before do
        described_class.call(event_type: "order.created", payload: { order_id: 1 }, idempotency_key: key)
      end

      it "does not create a second Event" do
        expect do
          described_class.call(event_type: "order.created", payload: { order_id: 1 }, idempotency_key: key)
        end.not_to change(Hookshot::Event, :count)
      end

      it "returns the existing Event" do
        existing = Hookshot::Event.find_by(idempotency_key: key)
        result   = described_class.call(event_type: "order.created", payload: { order_id: 1 }, idempotency_key: key)
        expect(result).to eq(existing)
      end

      it "does not enqueue additional jobs" do
        expect do
          described_class.call(event_type: "order.created", payload: { order_id: 1 }, idempotency_key: key)
        end.not_to have_enqueued_job(Hookshot::DeliveryJob)
      end
    end

    # ── Endpoint status filtering ────────────────────────────────────────────

    context "when the endpoint is paused" do
      let!(:endpoint) { create(:hookshot_endpoint, :paused) }

      it "creates no deliveries" do
        expect { dispatch }.not_to change(Hookshot::Delivery, :count)
      end

      it "enqueues no jobs" do
        expect { dispatch }.not_to have_enqueued_job(Hookshot::DeliveryJob)
      end
    end

    context "when the endpoint has an open circuit breaker" do
      let!(:endpoint) { create(:hookshot_endpoint, :circuit_open) }

      it "creates no deliveries" do
        expect { dispatch }.not_to change(Hookshot::Delivery, :count)
      end

      it "enqueues no jobs" do
        expect { dispatch }.not_to have_enqueued_job(Hookshot::DeliveryJob)
      end
    end

    context "when no endpoints are subscribed to the event_type" do
      subject(:dispatch) do
        described_class.call(event_type: "user.deleted", payload: {})
      end

      it "still creates the event" do
        expect { dispatch }.to change(Hookshot::Event, :count).by(1)
      end

      it "creates no deliveries" do
        expect { dispatch }.not_to change(Hookshot::Delivery, :count)
      end
    end
  end
end
