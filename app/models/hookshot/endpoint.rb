# frozen_string_literal: true

module Hookshot
  # Represents a registered webhook receiver.
  #
  # Each endpoint has a URL, a per-endpoint secret for HMAC signing, and a
  # circuit breaker status. The secret is auto-generated on create if not provided.
  class Endpoint < ApplicationRecord
    has_many :subscriptions, dependent: :destroy, class_name: "Hookshot::Subscription"
    has_many :deliveries, dependent: :destroy, class_name: "Hookshot::Delivery"
    has_many :dead_letters, dependent: :destroy, class_name: "Hookshot::DeadLetter"

    accepts_nested_attributes_for :subscriptions, allow_destroy: true

    enum :status, { active: 0, paused: 1, circuit_open: 2 }, prefix: true

    validates :url, presence: true,
                    uniqueness: true,
                    format: {
                      with: URI::RFC2396_PARSER.make_regexp(%w[http https]),
                      message: "must be a valid HTTP or HTTPS URL",
                    }
    validates :secret, presence: true
    validates :consecutive_failures, numericality: { greater_than_or_equal_to: 0 }

    # Auto-generate secret before validation so presence check still passes.
    before_validation :generate_secret, on: :create

    private

    def generate_secret
      self.secret ||= SecureRandom.hex(32)
    end
  end
end
