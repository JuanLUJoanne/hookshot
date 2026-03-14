# frozen_string_literal: true

require "rails_helper"

RSpec.describe Hookshot::Services::RetryPolicy do
  let(:delivery) { create(:hookshot_delivery, :failed, attempt_number: attempt_number) }

  # ── outcome ─────────────────────────────────────────────────────────────────

  describe ".outcome" do
    context "when attempt_number is below max_retries" do
      let(:attempt_number) { Hookshot.configuration.max_retries - 1 }

      it "returns :retry" do
        expect(described_class.outcome(delivery)).to eq(:retry)
      end
    end

    context "when attempt_number equals max_retries" do
      let(:attempt_number) { Hookshot.configuration.max_retries }

      it "returns :dead_letter" do
        expect(described_class.outcome(delivery)).to eq(:dead_letter)
      end
    end

    context "when attempt_number exceeds max_retries" do
      let(:attempt_number) { Hookshot.configuration.max_retries + 1 }

      it "returns :dead_letter" do
        expect(described_class.outcome(delivery)).to eq(:dead_letter)
      end
    end
  end

  # ── next_delay ───────────────────────────────────────────────────────────────

  describe ".next_delay" do
    let(:config) { Hookshot.configuration }

    it "applies exponential backoff: base_delay * 2^attempt" do
      # rand() in a class method is dispatched on self (RetryPolicy), so stub it directly.
      allow(described_class).to receive(:rand).and_return(0)
      delay = described_class.next_delay(1)
      expect(delay).to eq(config.retry_base_delay * (2**1))
    end

    it "adds jitter up to jitter_max" do
      allow(described_class).to receive(:rand).and_return(config.jitter_max)
      delay = described_class.next_delay(1)
      expect(delay).to eq((config.retry_base_delay * (2**1)) + config.jitter_max)
    end

    it "caps the delay at retry_max_delay" do
      # Use a very high attempt number to exceed the cap
      delay = described_class.next_delay(20)
      expect(delay).to be <= config.retry_max_delay
    end

    it "returns a delay within the expected range for attempt 1" do
      config = Hookshot.configuration
      min_delay = config.retry_base_delay * 2
      max_delay = [min_delay + config.jitter_max, config.retry_max_delay].min
      delay = described_class.next_delay(1)
      expect(delay).to be_between(min_delay, max_delay)
    end
  end

  # ── handle_outcome ────────────────────────────────────────────────────────────

  describe ".handle_outcome" do
    context "when the delivery succeeded" do
      let(:delivery) { create(:hookshot_delivery, :success, attempt_number: 1) }

      it "does not enqueue a RetryJob" do
        expect { described_class.handle_outcome(delivery) }.not_to have_enqueued_job(Hookshot::RetryJob)
      end

      it "does not create a DeadLetter" do
        expect { described_class.handle_outcome(delivery) }.not_to change(Hookshot::DeadLetter, :count)
      end
    end

    context "when the delivery failed and should be retried" do
      let(:attempt_number) { 1 }

      it "enqueues a RetryJob" do
        expect { described_class.handle_outcome(delivery) }.to have_enqueued_job(Hookshot::RetryJob)
          .with(delivery.id)
      end

      it "does not create a DeadLetter" do
        expect { described_class.handle_outcome(delivery) }.not_to change(Hookshot::DeadLetter, :count)
      end
    end

    context "when the delivery has exceeded max_retries" do
      let(:attempt_number) { Hookshot.configuration.max_retries }

      it "creates a DeadLetter record" do
        expect { described_class.handle_outcome(delivery) }.to change(Hookshot::DeadLetter, :count).by(1)
      end

      it "marks the DeadLetter with reason max_retries_exceeded" do
        described_class.handle_outcome(delivery)
        expect(Hookshot::DeadLetter.last.reason).to eq("max_retries_exceeded")
      end

      it "marks the associated event as failed" do
        described_class.handle_outcome(delivery)
        expect(delivery.event.reload.status).to eq("failed")
      end

      it "does not enqueue a RetryJob" do
        expect { described_class.handle_outcome(delivery) }.not_to have_enqueued_job(Hookshot::RetryJob)
      end
    end

    context "when the delivery has circuit_open status" do
      let(:delivery) { create(:hookshot_delivery, :circuit_open, attempt_number: 1) }

      it "does not enqueue a RetryJob" do
        expect { described_class.handle_outcome(delivery) }.not_to have_enqueued_job(Hookshot::RetryJob)
      end

      it "does not create a DeadLetter" do
        expect { described_class.handle_outcome(delivery) }.not_to change(Hookshot::DeadLetter, :count)
      end
    end
  end
end
