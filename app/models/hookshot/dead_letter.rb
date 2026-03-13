# frozen_string_literal: true

module Hookshot
  # Holds deliveries that have exhausted all retry attempts.
  #
  # A DeadLetter is created when a Delivery's attempt count reaches
  # config.max_retries, or when the circuit breaker is open at dispatch time.
  # Entries can be manually retried from the dashboard or via the API.
  class DeadLetter < ApplicationRecord
    belongs_to :delivery, class_name: "Hookshot::Delivery"
    belongs_to :event, class_name: "Hookshot::Event"
    belongs_to :endpoint, class_name: "Hookshot::Endpoint"

    enum :reason, { max_retries_exceeded: 0, circuit_open: 1, manual: 2 }, prefix: true

    validates :reason, presence: true
    validates :total_attempts, numericality: { greater_than: 0 }, allow_nil: true
  end
end
