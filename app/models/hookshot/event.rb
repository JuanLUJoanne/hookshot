# frozen_string_literal: true

module Hookshot
  # Represents a webhook event dispatched by the host application.
  #
  # Events fan out to all endpoints subscribed to the event_type. Each Event
  # has a unique idempotency_key (auto-generated UUID) to prevent duplicate
  # processing when Hookshot.trigger is called multiple times with the same key.
  class Event < ApplicationRecord
    has_many :deliveries, dependent: :destroy, class_name: "Hookshot::Delivery"
    has_many :dead_letters, dependent: :destroy, class_name: "Hookshot::DeadLetter"

    enum :status, { pending: 0, dispatched: 1, completed: 2, failed: 3 }, prefix: true

    validates :event_type, presence: true
    validates :idempotency_key, presence: true, uniqueness: true

    # Auto-generate idempotency_key before validation so the presence check passes
    # and callers can omit it to get automatic UUID assignment.
    before_validation :generate_idempotency_key, on: :create

    private

    def generate_idempotency_key
      self.idempotency_key ||= SecureRandom.uuid
    end
  end
end
