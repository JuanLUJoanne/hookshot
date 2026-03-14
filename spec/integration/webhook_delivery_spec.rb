# frozen_string_literal: true

require "rails_helper"

# Integration specs exercise the full pipeline from Hookshot.trigger through
# job execution to final delivery state. Jobs are run inline via
# perform_enqueued_jobs; HTTP is stubbed with WebMock.
RSpec.describe "Webhook Delivery Pipeline" do
  include ActiveJob::TestHelper

  let(:endpoint) { create(:hookshot_endpoint) }

  before do
    create(:hookshot_subscription, endpoint:, event_type: "order.created")
  end

  after { Hookshot.reset_configuration! }

  # ── Happy path ─────────────────────────────────────────────────────────────

  describe "successful delivery" do
    before do
      stub_request(:post, endpoint.url)
        .to_return(status: 200, body: '{"ok":true}', headers: { "Content-Type" => "application/json" })
    end

    it "creates an Event record" do
      expect do
        perform_enqueued_jobs { Hookshot.trigger("order.created", payload: { order_id: 42 }) }
      end.to change(Hookshot::Event, :count).by(1)
    end

    it "creates a Delivery record" do
      expect do
        perform_enqueued_jobs { Hookshot.trigger("order.created", payload: { order_id: 42 }) }
      end.to change(Hookshot::Delivery, :count).by(1)
    end

    it "marks the delivery as success" do
      perform_enqueued_jobs { Hookshot.trigger("order.created", payload: { order_id: 42 }) }

      expect(Hookshot::Delivery.last).to be_status_success
    end

    it "records the HTTP response status on the delivery" do
      perform_enqueued_jobs { Hookshot.trigger("order.created", payload: { order_id: 42 }) }

      expect(Hookshot::Delivery.last.response_status).to eq(200)
    end

    it "records the response body on the delivery" do
      perform_enqueued_jobs { Hookshot.trigger("order.created", payload: { order_id: 42 }) }

      expect(Hookshot::Delivery.last.response_body).to eq('{"ok":true}')
    end

    it "sets delivered_at on the delivery" do
      perform_enqueued_jobs { Hookshot.trigger("order.created", payload: { order_id: 42 }) }

      expect(Hookshot::Delivery.last.delivered_at).not_to be_nil
    end

    it "records HMAC signature headers on the delivery" do
      perform_enqueued_jobs { Hookshot.trigger("order.created", payload: { order_id: 42 }) }

      headers = Hookshot::Delivery.last.request_headers
      expect(headers).to have_key("X-Hookshot-Signature")
      expect(headers).to have_key("X-Hookshot-Timestamp")
    end

    it "records the event type header on the delivery" do
      perform_enqueued_jobs { Hookshot.trigger("order.created", payload: { order_id: 42 }) }

      expect(Hookshot::Delivery.last.request_headers["X-Hookshot-Event"]).to eq("order.created")
    end

    it "records a duration_ms on the delivery" do
      perform_enqueued_jobs { Hookshot.trigger("order.created", payload: { order_id: 42 }) }

      expect(Hookshot::Delivery.last.duration_ms).to be >= 0
    end

    it "returns the created Event from trigger" do
      event = nil
      perform_enqueued_jobs { event = Hookshot.trigger("order.created", payload: { order_id: 42 }) }

      expect(event).to be_a(Hookshot::Event)
    end

    it "creates no DeadLetter records" do
      expect do
        perform_enqueued_jobs { Hookshot.trigger("order.created", payload: { order_id: 42 }) }
      end.not_to change(Hookshot::DeadLetter, :count)
    end
  end

  # ── 5xx → retry → success ──────────────────────────────────────────────────

  describe "retry after 5xx failure" do
    before do
      stub_request(:post, endpoint.url)
        .to_return(status: 503, body: "Service Unavailable")
        .then
        .to_return(status: 200, body: '{"ok":true}')
    end

    it "creates two Delivery records (one per attempt)" do
      perform_enqueued_jobs { Hookshot.trigger("order.created", payload: { order_id: 42 }) }

      expect(Hookshot::Delivery.count).to eq(2)
    end

    it "marks the first attempt as failed" do
      perform_enqueued_jobs { Hookshot.trigger("order.created", payload: { order_id: 42 }) }

      first = Hookshot::Delivery.order(attempt_number: :asc).first
      expect(first).to be_status_failed
    end

    it "marks the retry attempt as success" do
      perform_enqueued_jobs { Hookshot.trigger("order.created", payload: { order_id: 42 }) }

      retry_attempt = Hookshot::Delivery.order(attempt_number: :asc).last
      expect(retry_attempt).to be_status_success
    end

    it "sets attempt_number to 2 on the retry delivery" do
      perform_enqueued_jobs { Hookshot.trigger("order.created", payload: { order_id: 42 }) }

      expect(Hookshot::Delivery.order(attempt_number: :asc).last.attempt_number).to eq(2)
    end

    it "creates no DeadLetter records when retry succeeds" do
      expect do
        perform_enqueued_jobs { Hookshot.trigger("order.created", payload: { order_id: 42 }) }
      end.not_to change(Hookshot::DeadLetter, :count)
    end
  end

  # ── Dead letter after max retries ──────────────────────────────────────────

  describe "dead-lettering after max retries are exhausted" do
    # max_retries=2 → attempt 1 fails (1 < 2 → retry), attempt 2 fails (2 >= 2 → dead letter)
    before do
      Hookshot.configure { |c| c.max_retries = 2 }
      stub_request(:post, endpoint.url).to_return(status: 503, body: "Service Unavailable")
    end

    it "creates a DeadLetter record" do
      expect do
        perform_enqueued_jobs { Hookshot.trigger("order.created", payload: { order_id: 42 }) }
      end.to change(Hookshot::DeadLetter, :count).by(1)
    end

    it "sets the dead letter reason to max_retries_exceeded" do
      perform_enqueued_jobs { Hookshot.trigger("order.created", payload: { order_id: 42 }) }

      expect(Hookshot::DeadLetter.last.reason).to eq("max_retries_exceeded")
    end

    it "marks the event as failed" do
      perform_enqueued_jobs { Hookshot.trigger("order.created", payload: { order_id: 42 }) }

      expect(Hookshot::Event.last).to be_status_failed
    end

    it "records total_attempts on the dead letter" do
      perform_enqueued_jobs { Hookshot.trigger("order.created", payload: { order_id: 42 }) }

      expect(Hookshot::DeadLetter.last.total_attempts).to eq(2)
    end

    it "creates two Delivery records representing all attempts" do
      perform_enqueued_jobs { Hookshot.trigger("order.created", payload: { order_id: 42 }) }

      expect(Hookshot::Delivery.count).to eq(2)
    end

    it "associates the dead letter with the correct endpoint" do
      perform_enqueued_jobs { Hookshot.trigger("order.created", payload: { order_id: 42 }) }

      expect(Hookshot::DeadLetter.last.endpoint).to eq(endpoint)
    end
  end

  # ── Network timeout ────────────────────────────────────────────────────────

  describe "network timeout handling" do
    before do
      # max_retries=1 → attempt 1 times out (1 >= 1 → dead letter immediately)
      Hookshot.configure { |c| c.max_retries = 1 }
      stub_request(:post, endpoint.url).to_timeout
    end

    it "records the delivery as failed" do
      perform_enqueued_jobs { Hookshot.trigger("order.created", payload: { order_id: 42 }) }

      expect(Hookshot::Delivery.last).to be_status_failed
    end

    it "records an error_message on the failed delivery" do
      perform_enqueued_jobs { Hookshot.trigger("order.created", payload: { order_id: 42 }) }

      expect(Hookshot::Delivery.last.error_message).not_to be_nil
    end

    it "dead-letters after max retries" do
      expect do
        perform_enqueued_jobs { Hookshot.trigger("order.created", payload: { order_id: 42 }) }
      end.to change(Hookshot::DeadLetter, :count).by(1)
    end
  end

  # ── Connection refused ─────────────────────────────────────────────────────

  describe "connection refused handling" do
    before do
      Hookshot.configure { |c| c.max_retries = 1 }
      stub_request(:post, endpoint.url).to_raise(Errno::ECONNREFUSED)
    end

    it "records the delivery as failed" do
      perform_enqueued_jobs { Hookshot.trigger("order.created", payload: { order_id: 42 }) }

      expect(Hookshot::Delivery.last).to be_status_failed
    end

    it "records the error message on the delivery" do
      perform_enqueued_jobs { Hookshot.trigger("order.created", payload: { order_id: 42 }) }

      expect(Hookshot::Delivery.last.error_message).not_to be_nil
    end
  end

  # ── Idempotency ────────────────────────────────────────────────────────────

  describe "idempotent trigger" do
    let(:key) { SecureRandom.uuid }

    before do
      stub_request(:post, endpoint.url).to_return(status: 200, body: '{"ok":true}')
    end

    it "returns the existing Event when the same key is used twice" do
      first  = Hookshot.trigger("order.created", payload: { order_id: 1 }, idempotency_key: key)
      second = Hookshot.trigger("order.created", payload: { order_id: 1 }, idempotency_key: key)

      expect(second.id).to eq(first.id)
    end

    it "does not create a second Event on duplicate trigger" do
      Hookshot.trigger("order.created", payload: { order_id: 1 }, idempotency_key: key)

      expect do
        Hookshot.trigger("order.created", payload: { order_id: 1 }, idempotency_key: key)
      end.not_to change(Hookshot::Event, :count)
    end

    it "does not enqueue additional jobs on duplicate trigger" do
      Hookshot.trigger("order.created", payload: { order_id: 1 }, idempotency_key: key)

      expect do
        Hookshot.trigger("order.created", payload: { order_id: 1 }, idempotency_key: key)
      end.not_to have_enqueued_job(Hookshot::DeliveryJob)
    end
  end

  # ── Paused endpoint ────────────────────────────────────────────────────────

  describe "paused endpoint" do
    let(:endpoint) { create(:hookshot_endpoint, :paused) }

    it "creates the Event" do
      expect do
        Hookshot.trigger("order.created", payload: { order_id: 42 })
      end.to change(Hookshot::Event, :count).by(1)
    end

    it "creates no Delivery records" do
      expect do
        Hookshot.trigger("order.created", payload: { order_id: 42 })
      end.not_to change(Hookshot::Delivery, :count)
    end

    it "enqueues no DeliveryJobs" do
      expect do
        Hookshot.trigger("order.created", payload: { order_id: 42 })
      end.not_to have_enqueued_job(Hookshot::DeliveryJob)
    end
  end

  # ── Circuit-open endpoint ──────────────────────────────────────────────────

  describe "circuit-open endpoint" do
    let(:endpoint) { create(:hookshot_endpoint, :circuit_open) }

    it "creates the Event" do
      expect do
        Hookshot.trigger("order.created", payload: { order_id: 42 })
      end.to change(Hookshot::Event, :count).by(1)
    end

    it "creates no Delivery records" do
      expect do
        Hookshot.trigger("order.created", payload: { order_id: 42 })
      end.not_to change(Hookshot::Delivery, :count)
    end

    it "enqueues no DeliveryJobs" do
      expect do
        Hookshot.trigger("order.created", payload: { order_id: 42 })
      end.not_to have_enqueued_job(Hookshot::DeliveryJob)
    end
  end

  # ── No subscriptions ───────────────────────────────────────────────────────

  describe "event with no subscribed endpoints" do
    it "creates the Event" do
      expect do
        Hookshot.trigger("user.deleted", payload: { user_id: 99 })
      end.to change(Hookshot::Event, :count).by(1)
    end

    it "creates no Delivery records" do
      expect do
        Hookshot.trigger("user.deleted", payload: { user_id: 99 })
      end.not_to change(Hookshot::Delivery, :count)
    end
  end

  # ── Fan-out to multiple endpoints ──────────────────────────────────────────

  describe "fan-out to multiple subscribed endpoints" do
    let(:endpoint2) { create(:hookshot_endpoint) }

    before do
      create(:hookshot_subscription, endpoint: endpoint2, event_type: "order.created")
      stub_request(:post, endpoint.url).to_return(status: 200, body: '{"ok":true}')
      stub_request(:post, endpoint2.url).to_return(status: 200, body: '{"ok":true}')
    end

    it "creates one Delivery per endpoint" do
      expect do
        perform_enqueued_jobs { Hookshot.trigger("order.created", payload: { order_id: 42 }) }
      end.to change(Hookshot::Delivery, :count).by(2)
    end

    it "marks all deliveries as success" do
      perform_enqueued_jobs { Hookshot.trigger("order.created", payload: { order_id: 42 }) }

      expect(Hookshot::Delivery.all).to all(be_status_success)
    end

    it "enqueues one DeliveryJob per endpoint" do
      expect do
        Hookshot.trigger("order.created", payload: { order_id: 42 })
      end.to have_enqueued_job(Hookshot::DeliveryJob).exactly(:twice)
    end
  end

  # ── Endpoint not subscribed to this event_type ─────────────────────────────

  describe "endpoint subscribed to a different event_type" do
    before do
      # endpoint is subscribed to "order.created" (set up in outer before),
      # but we fire "payment.failed" — no match.
      stub_request(:post, endpoint.url).to_return(status: 200, body: '{"ok":true}')
    end

    it "creates the Event" do
      expect do
        Hookshot.trigger("payment.failed", payload: { amount: "50.00" })
      end.to change(Hookshot::Event, :count).by(1)
    end

    it "creates no Delivery records for the non-subscribed event" do
      expect do
        Hookshot.trigger("payment.failed", payload: { amount: "50.00" })
      end.not_to change(Hookshot::Delivery, :count)
    end
  end
end
