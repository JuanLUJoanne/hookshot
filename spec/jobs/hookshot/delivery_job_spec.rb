# frozen_string_literal: true

require "rails_helper"

RSpec.describe Hookshot::DeliveryJob do
  describe "#perform" do
    let(:endpoint) { create(:hookshot_endpoint) }
    let(:event)    { create(:hookshot_event) }
    let(:delivery) { create(:hookshot_delivery, endpoint:, event:, status: :pending) }

    before do
      stub_request(:post, endpoint.url).to_return(status: 200, body: '{"ok":true}')
    end

    context "when the delivery is pending" do
      it "calls DeliveryExecutor with the delivery" do
        allow(Hookshot::Services::DeliveryExecutor).to receive(:call).and_return(delivery)
        allow(Hookshot::Services::RetryPolicy).to receive(:handle_outcome)

        described_class.perform_now(delivery.id)

        expect(Hookshot::Services::DeliveryExecutor).to have_received(:call).with(delivery)
      end

      it "calls RetryPolicy.handle_outcome after execution" do
        allow(Hookshot::Services::DeliveryExecutor).to receive(:call).and_return(delivery)
        allow(Hookshot::Services::RetryPolicy).to receive(:handle_outcome)

        described_class.perform_now(delivery.id)

        expect(Hookshot::Services::RetryPolicy).to have_received(:handle_outcome).with(delivery)
      end
    end

    # ── Idempotency guard ────────────────────────────────────────────────────

    context "when the delivery is already succeeded (duplicate job execution)" do
      let(:delivery) { create(:hookshot_delivery, :success, endpoint:, event:) }

      it "does not call DeliveryExecutor" do
        allow(Hookshot::Services::DeliveryExecutor).to receive(:call)

        described_class.perform_now(delivery.id)

        expect(Hookshot::Services::DeliveryExecutor).not_to have_received(:call)
      end
    end

    context "when the delivery is in failed status" do
      let(:delivery) { create(:hookshot_delivery, :failed, endpoint:, event:) }

      it "does not call DeliveryExecutor" do
        allow(Hookshot::Services::DeliveryExecutor).to receive(:call)

        described_class.perform_now(delivery.id)

        expect(Hookshot::Services::DeliveryExecutor).not_to have_received(:call)
      end
    end

    # ── Missing record ───────────────────────────────────────────────────────

    context "when the delivery record no longer exists" do
      it "does not raise an error" do
        expect { described_class.perform_now(999_999) }.not_to raise_error
      end

      it "does not call DeliveryExecutor" do
        allow(Hookshot::Services::DeliveryExecutor).to receive(:call)

        described_class.perform_now(999_999)

        expect(Hookshot::Services::DeliveryExecutor).not_to have_received(:call)
      end
    end

    # ── Queue configuration ──────────────────────────────────────────────────

    it "is enqueued on the configured queue" do
      expect { described_class.perform_later(delivery.id) }
        .to have_enqueued_job(described_class).on_queue(Hookshot.configuration.queue_name.to_s)
    end
  end
end
