# frozen_string_literal: true

module Hookshot
  module Services
    # Dispatches a webhook event to all subscribed, active endpoints.
    #
    # Creates the Event record, fans out to matching endpoints, creates one
    # Delivery per endpoint, and enqueues a DeliveryJob for each — all inside
    # a single database transaction. Because Solid Queue is DB-backed, the job
    # enqueue is part of the same transaction as the records, giving us atomic
    # consistency between what exists in the DB and what is queued (ADR-002).
    #
    # @example
    #   event = Hookshot::Services::EventDispatcher.call(
    #     event_type:      "order.created",
    #     payload:         { order_id: 42, total: "99.99" },
    #     idempotency_key: "my-uuid",   # optional
    #   )
    class EventDispatcher
      # @param event_type [String] e.g. "order.created"
      # @param payload [Hash] event data; serialized to JSON at delivery time
      # @param idempotency_key [String, nil] caller-supplied key; UUID generated if nil
      # @return [Hookshot::Event] the created (or pre-existing) event
      def self.call(event_type:, payload:, idempotency_key: nil)
        new(event_type:, payload:, idempotency_key:).call
      end

      def initialize(event_type:, payload:, idempotency_key: nil)
        @event_type      = event_type
        @payload         = payload
        @idempotency_key = idempotency_key || SecureRandom.uuid
      end

      def call
        # Return the existing event without re-dispatching if the key was already used.
        # Callers can safely retry trigger() after a crash without creating duplicates.
        existing = Event.find_by(idempotency_key: @idempotency_key)
        return existing if existing

        ActiveRecord::Base.transaction do
          event = create_event
          deliveries = create_deliveries(event)
          enqueue_jobs(deliveries)
          event.status_dispatched!
          event
        end
      end

      private

      attr_reader :event_type, :payload, :idempotency_key

      def create_event
        Event.create!(event_type:, payload:, idempotency_key:)
      end

      # Only active endpoints subscribed to this event_type receive deliveries.
      # Paused and circuit-open endpoints are skipped entirely at dispatch time.
      def subscribed_endpoints
        Endpoint
          .status_active
          .joins(:subscriptions)
          .where(hookshot_subscriptions: { event_type: })
      end

      def create_deliveries(event)
        subscribed_endpoints.map do |endpoint|
          Delivery.create!(event:, endpoint:, status: :pending)
        end
      end

      def enqueue_jobs(deliveries)
        deliveries.each { |delivery| Hookshot::DeliveryJob.perform_later(delivery.id) }
      end
    end
  end
end
