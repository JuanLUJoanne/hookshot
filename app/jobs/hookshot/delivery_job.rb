# frozen_string_literal: true

module Hookshot
  # Executes a single webhook delivery attempt.
  #
  # Called immediately by EventDispatcher for fresh deliveries. On failure,
  # delegates to RetryPolicy which decides whether to schedule a RetryJob or
  # move the delivery to the dead-letter queue.
  class DeliveryJob < ApplicationJob
    # @param delivery_id [Integer] primary key of the Delivery record
    def perform(delivery_id)
      delivery = Delivery.find_by(id: delivery_id)
      return unless delivery
      # Guard against duplicate job execution (e.g. Solid Queue at-least-once).
      return unless delivery.status_pending?

      Services::DeliveryExecutor.call(delivery)
      Services::RetryPolicy.handle_outcome(delivery)
    end
  end
end
