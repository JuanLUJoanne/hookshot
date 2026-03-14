# frozen_string_literal: true

require "active_support/security_utils"

module Hookshot
  module Services
    # Verifies an inbound webhook signature to confirm payload authenticity.
    #
    # Two checks are performed:
    #   1. Timestamp freshness — rejects requests older than REPLAY_TOLERANCE
    #      to prevent replay attacks even if a valid signature is intercepted.
    #   2. Signature equality — constant-time comparison via secure_compare
    #      to prevent timing-based oracle attacks.
    #
    # @example (receiver side, inside a Rails controller)
    #   valid = Hookshot::Services::SignatureVerifier.valid?(
    #     payload:   request.body.read,
    #     signature: request.headers["X-Hookshot-Signature"],
    #     timestamp: request.headers["X-Hookshot-Timestamp"],
    #     secret:    ENV["WEBHOOK_SECRET"],
    #   )
    #   head :unauthorized unless valid
    class SignatureVerifier
      # Maximum age of a request timestamp we will accept, in seconds.
      REPLAY_TOLERANCE = 300 # 5 minutes

      # @param payload [String] raw request body
      # @param signature [String] value of X-Hookshot-Signature header
      # @param timestamp [String] value of X-Hookshot-Timestamp header (Unix seconds)
      # @param secret [String] the per-endpoint HMAC secret
      # @return [Boolean]
      def self.valid?(payload:, signature:, timestamp:, secret:)
        new(payload:, signature:, timestamp:, secret:).valid?
      end

      def initialize(payload:, signature:, timestamp:, secret:)
        @payload   = payload
        @signature = signature
        @timestamp = timestamp
        @secret    = secret
      end

      def valid?
        timestamp_fresh? && signatures_match?
      end

      private

      attr_reader :payload, :signature, :timestamp, :secret

      def timestamp_fresh?
        return false if timestamp.blank?

        elapsed = Time.now.to_i - timestamp.to_i
        elapsed.abs <= REPLAY_TOLERANCE
      end

      def signatures_match?
        return false if signature.blank?

        expected = Services::SignatureGenerator.call(
          payload:,
          secret:,
          timestamp: timestamp.to_i,
        )
        ActiveSupport::SecurityUtils.secure_compare(signature, expected[:signature])
      end
    end
  end
end
