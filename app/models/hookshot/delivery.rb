# frozen_string_literal: true

module Hookshot
  # Represents a single delivery attempt for an event to an endpoint.
  #
  # Each retry creates a NEW Delivery record (see ADR-005). This preserves a
  # complete audit trail: every attempt with its HTTP response, latency, and
  # error detail is independently addressable and queryable.
  class Delivery < ApplicationRecord
    belongs_to :event, class_name: "Hookshot::Event"
    belongs_to :endpoint, class_name: "Hookshot::Endpoint"
    has_one :dead_letter, dependent: :destroy, class_name: "Hookshot::DeadLetter"

    enum :status, { pending: 0, success: 1, failed: 2, circuit_open: 3 }, prefix: true

    validates :idempotency_key, presence: true, uniqueness: true
    validates :attempt_number, numericality: { greater_than: 0 }

    before_validation :generate_idempotency_key, on: :create

    private

    def generate_idempotency_key
      self.idempotency_key ||= SecureRandom.uuid
    end
  end
end
