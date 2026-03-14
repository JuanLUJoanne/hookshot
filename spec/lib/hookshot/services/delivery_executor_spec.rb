# frozen_string_literal: true

require "rails_helper"

RSpec.describe Hookshot::Services::DeliveryExecutor do
  subject(:execute) { described_class.call(delivery) }

  let(:endpoint) { create(:hookshot_endpoint, secret: "test-secret-abc") }
  let(:event)    { create(:hookshot_event, payload: { order_id: 42 }) }
  let(:delivery) { create(:hookshot_delivery, endpoint:, event:) }

  # ── Successful delivery ──────────────────────────────────────────────────────

  describe ".call" do
    context "when the endpoint returns 200" do
      before do
        stub_request(:post, endpoint.url)
          .to_return(status: 200, body: '{"ok":true}', headers: { "Content-Type" => "application/json" })
      end

      it "updates the delivery status to success" do
        execute
        expect(delivery.reload.status).to eq("success")
      end

      it "records the response status code" do
        execute
        expect(delivery.reload.response_status).to eq(200)
      end

      it "records the response body" do
        execute
        expect(delivery.reload.response_body).to eq('{"ok":true}')
      end

      it "records the delivered_at timestamp" do
        execute
        expect(delivery.reload.delivered_at).not_to be_nil
      end

      it "records the duration_ms" do
        execute
        expect(delivery.reload.duration_ms).to be_a(Integer)
      end

      it "sends the Content-Type header" do
        execute
        expect(
          a_request(:post, endpoint.url).with(headers: { "Content-Type" => "application/json" }),
        ).to have_been_made
      end

      it "sends the X-Hookshot-Event header" do
        execute
        expect(
          a_request(:post, endpoint.url).with(headers: { "X-Hookshot-Event" => event.event_type }),
        ).to have_been_made
      end

      it "sends the X-Hookshot-Delivery idempotency header" do
        execute
        expect(
          a_request(:post, endpoint.url).with(headers: { "X-Hookshot-Delivery" => delivery.idempotency_key }),
        ).to have_been_made
      end

      it "sends a valid X-Hookshot-Signature header" do
        execute
        expect(
          a_request(:post, endpoint.url).with(headers: { "X-Hookshot-Signature" => /\Asha256=/ }),
        ).to have_been_made
      end

      it "sends a X-Hookshot-Timestamp header" do
        execute
        expect(
          a_request(:post, endpoint.url).with(headers: { "X-Hookshot-Timestamp" => /\A\d+\z/ }),
        ).to have_been_made
      end
    end

    context "when the endpoint returns a 2xx status other than 200" do
      before do
        stub_request(:post, endpoint.url).to_return(status: 201, body: "")
      end

      it "records success" do
        execute
        expect(delivery.reload.status).to eq("success")
      end
    end

    # ── Server errors ────────────────────────────────────────────────────────

    context "when the endpoint returns 500" do
      before do
        stub_request(:post, endpoint.url).to_return(status: 500, body: "Internal Server Error")
      end

      it "updates the delivery status to failed" do
        execute
        expect(delivery.reload.status).to eq("failed")
      end

      it "records the response status code" do
        execute
        expect(delivery.reload.response_status).to eq(500)
      end

      it "does not set delivered_at" do
        execute
        expect(delivery.reload.delivered_at).to be_nil
      end
    end

    context "when the endpoint returns 503" do
      before do
        stub_request(:post, endpoint.url).to_return(status: 503, body: "Service Unavailable")
      end

      it "updates the delivery status to failed" do
        execute
        expect(delivery.reload.status).to eq("failed")
      end
    end

    # ── Network errors ───────────────────────────────────────────────────────

    context "when the request times out" do
      before { stub_request(:post, endpoint.url).to_timeout }

      it "updates the delivery status to failed" do
        execute
        expect(delivery.reload.status).to eq("failed")
      end

      it "records the error message" do
        execute
        expect(delivery.reload.error_message).not_to be_blank
      end

      it "does not raise an exception" do
        expect { execute }.not_to raise_error
      end
    end

    context "when the connection is refused" do
      before { stub_request(:post, endpoint.url).to_raise(Errno::ECONNREFUSED) }

      it "updates the delivery status to failed" do
        execute
        expect(delivery.reload.status).to eq("failed")
      end

      it "records the error message" do
        execute
        expect(delivery.reload.error_message).not_to be_blank
      end

      it "does not raise an exception" do
        expect { execute }.not_to raise_error
      end
    end

    context "when the connection is reset" do
      before { stub_request(:post, endpoint.url).to_raise(Errno::ECONNRESET) }

      it "updates the delivery status to failed" do
        execute
        expect(delivery.reload.status).to eq("failed")
      end

      it "does not raise an exception" do
        expect { execute }.not_to raise_error
      end
    end

    context "when DNS resolution fails" do
      before { stub_request(:post, endpoint.url).to_raise(SocketError) }

      it "updates the delivery status to failed" do
        execute
        expect(delivery.reload.status).to eq("failed")
      end

      it "does not raise an exception" do
        expect { execute }.not_to raise_error
      end
    end

    # ── HMAC signature correctness ───────────────────────────────────────────

    context "with HMAC signature verification" do
      let(:captured_headers) { {} }

      before do
        stub_request(:post, endpoint.url)
          .to_return(status: 200, body: "")
      end

      it "generates a signature that the verifier accepts" do
        execute

        request = WebMock::RequestRegistry.instance.requested_signatures.hash.keys.first
        sig     = request.headers["X-Hookshot-Signature"]
        ts      = request.headers["X-Hookshot-Timestamp"]
        body    = JSON.generate(event.payload)

        valid = Hookshot::Services::SignatureVerifier.valid?(
          payload: body,
          signature: sig,
          timestamp: ts,
          secret: endpoint.secret,
        )
        expect(valid).to be(true)
      end
    end
  end
end
