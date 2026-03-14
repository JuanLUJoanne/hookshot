# frozen_string_literal: true

require "openssl"

module Hookshot
  module Services
    # Generates an HMAC-SHA256 signature for a webhook payload.
    #
    # The signed string is constructed as "{timestamp}.{payload}" — binding the
    # timestamp to the signature prevents a valid signature being replayed later
    # with a repackaged body. Receivers check the timestamp in X-Hookshot-Timestamp
    # and reject requests outside the tolerance window.
    #
    # @example
    #   result = Hookshot::Services::SignatureGenerator.call(
    #     payload: '{"order_id":1}',
    #     secret:  endpoint.secret,
    #   )
    #   result[:signature]  # => "sha256=abc123..."
    #   result[:timestamp]  # => "1710364800"
    class SignatureGenerator
      ALGORITHM = "sha256"

      # Computes the HMAC signature for a payload.
      #
      # @param payload [String] the raw request body (JSON string)
      # @param secret [String] the per-endpoint HMAC secret
      # @param timestamp [Integer, nil] Unix timestamp; defaults to current time
      # @return [Hash] with keys :signature (String, "sha256=<hex>") and :timestamp (String)
      def self.call(payload:, secret:, timestamp: nil)
        new(payload:, secret:, timestamp:).call
      end

      def initialize(payload:, secret:, timestamp: nil)
        @payload   = payload
        @secret    = secret
        @timestamp = (timestamp || Time.now.to_i).to_i
      end

      def call
        {
          signature: "#{ALGORITHM}=#{compute_hmac}",
          timestamp: @timestamp.to_s,
        }
      end

      private

      attr_reader :payload, :secret, :timestamp

      def compute_hmac
        signed_payload = "#{timestamp}.#{payload}"
        OpenSSL::HMAC.hexdigest(ALGORITHM, secret, signed_payload)
      end
    end
  end
end
