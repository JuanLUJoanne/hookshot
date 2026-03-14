# frozen_string_literal: true

require "rails_helper"

RSpec.describe Hookshot::RetryJob do
  describe "#perform" do
    let(:endpoint) { create(:hookshot_endpoint) }
    let(:event)    { create(:hookshot_event) }
    let(:original) { create(:hookshot_delivery, :failed, endpoint:, event:, attempt_number: 1) }

    before do
      stub_request(:post, endpoint.url).to_return(status: 200, body: '{"ok":true}')
    end

    # ── New delivery record ──────────────────────────────────────────────────

    context "when the original delivery exists" do
      it "creates a new Delivery record" do
        original # force creation before the change block measures the baseline
        expect { described_class.perform_now(original.id) }.to change(Hookshot::Delivery, :count).by(1)
      end

      it "increments the attempt_number on the new delivery" do
        described_class.perform_now(original.id)
        new_delivery = Hookshot::Delivery.order(:created_at).last
        expect(new_delivery.attempt_number).to eq(original.attempt_number + 1)
      end

      it "associates the new delivery with the same event" do
        described_class.perform_now(original.id)
        new_delivery = Hookshot::Delivery.order(:created_at).last
        expect(new_delivery.event).to eq(event)
      end

      it "associates the new delivery with the same endpoint" do
        described_class.perform_now(original.id)
        new_delivery = Hookshot::Delivery.order(:created_at).last
        expect(new_delivery.endpoint).to eq(endpoint)
      end

      it "calls DeliveryExecutor with the new delivery" do
        new_delivery = nil

        allow(Hookshot::Services::DeliveryExecutor).to receive(:call) do |d|
          new_delivery = d
          d
        end
        allow(Hookshot::Services::RetryPolicy).to receive(:handle_outcome)

        described_class.perform_now(original.id)

        expect(Hookshot::Services::DeliveryExecutor).to have_received(:call)
        expect(new_delivery).not_to eq(original)
        expect(new_delivery.attempt_number).to eq(2)
      end

      it "calls RetryPolicy.handle_outcome with the new delivery" do
        allow(Hookshot::Services::DeliveryExecutor).to receive(:call) { |d| d }
        captured = nil
        allow(Hookshot::Services::RetryPolicy).to receive(:handle_outcome) { |d| captured = d }

        described_class.perform_now(original.id)

        expect(captured).not_to be_nil
        expect(captured.attempt_number).to eq(2)
      end
    end

    # ── Missing original delivery ────────────────────────────────────────────

    context "when the original delivery no longer exists" do
      it "does not raise an error" do
        expect { described_class.perform_now(999_999) }.not_to raise_error
      end

      it "does not create a new Delivery" do
        expect { described_class.perform_now(999_999) }.not_to change(Hookshot::Delivery, :count)
      end

      it "does not call DeliveryExecutor" do
        allow(Hookshot::Services::DeliveryExecutor).to receive(:call)

        described_class.perform_now(999_999)

        expect(Hookshot::Services::DeliveryExecutor).not_to have_received(:call)
      end
    end

    # ── Queue configuration ──────────────────────────────────────────────────

    it "is enqueued on the configured queue" do
      expect { described_class.perform_later(original.id) }
        .to have_enqueued_job(described_class).on_queue(Hookshot.configuration.queue_name.to_s)
    end
  end
end
