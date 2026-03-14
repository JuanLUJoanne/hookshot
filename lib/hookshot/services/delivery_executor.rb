# frozen_string_literal: true

require "net/http"
require "json"

module Hookshot
  module Services
    # Performs the HTTP POST delivery of a webhook event to an endpoint.
    #
    # Signs the payload with HMAC-SHA256, POSTs it, and records the complete
    # request/response on the Delivery record regardless of outcome. The full
    # audit trail (headers, body, latency, error) is always written so operators
    # can diagnose failures without needing application logs.
    #
    # All known network failure modes are caught and converted to a failed
    # Delivery rather than letting exceptions propagate to the job layer — the
    # job layer's concern is orchestration (retry scheduling, dead-lettering),
    # not HTTP mechanics.
    class DeliveryExecutor
      NETWORK_ERRORS = [
        Timeout::Error,
        Net::OpenTimeout,
        Net::ReadTimeout,
        SocketError,
        Errno::ECONNREFUSED,
        Errno::ECONNRESET,
      ].freeze

      # @param delivery [Hookshot::Delivery]
      # @return [Hookshot::Delivery] the delivery record with status + response fields updated
      def self.call(delivery)
        new(delivery).call
      end

      def initialize(delivery)
        @delivery = delivery
        @config   = Hookshot.configuration
      end

      def call
        body           = JSON.generate(event.payload)
        signature_data = SignatureGenerator.call(payload: body, secret: endpoint.secret)
        headers        = build_headers(signature_data)

        perform_request(body, headers)
      end

      private

      attr_reader :delivery, :config

      def event    = delivery.event
      def endpoint = delivery.endpoint

      def build_headers(signature_data)
        {
          "Content-Type" => "application/json",
          "X-Hookshot-Signature" => signature_data[:signature],
          "X-Hookshot-Timestamp" => signature_data[:timestamp],
          "X-Hookshot-Delivery" => delivery.idempotency_key,
          "X-Hookshot-Event" => event.event_type,
        }
      end

      def perform_request(body, headers)
        start    = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        response = post(endpoint.url, body, headers)
        record_success(response, headers, elapsed_ms(start))
      rescue *NETWORK_ERRORS => e
        record_network_error(e, headers, elapsed_ms(start))
      end

      def post(url, body, headers)
        uri      = URI(url)
        req      = Net::HTTP::Post.new(uri.request_uri, headers)
        req.body = body
        build_http(uri).request(req)
      end

      def build_http(uri)
        Net::HTTP.new(uri.host, uri.port).tap do |http|
          http.use_ssl      = (uri.scheme == "https")
          http.open_timeout = config.connect_timeout
          http.read_timeout = config.read_timeout
        end
      end

      def record_success(response, headers, duration_ms)
        success = (200..299).cover?(response.code.to_i)
        delivery.update!(
          status: success ? :success : :failed,
          response_status: response.code.to_i,
          response_body: response.body,
          response_headers: response.to_hash,
          request_headers: headers,
          duration_ms:,
          delivered_at: success ? Time.current : nil,
        )
        delivery
      end

      def record_network_error(error, headers, duration_ms)
        delivery.update!(
          status: :failed,
          error_message: error.message,
          request_headers: headers,
          duration_ms:,
        )
        delivery
      end

      def elapsed_ms(start)
        ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round
      end
    end
  end
end
