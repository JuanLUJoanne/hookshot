# frozen_string_literal: true

module Hookshot
  # Executes a retry delivery attempt, creating a new Delivery record for
  # each attempt to preserve a complete audit trail (ADR-005).
  #
  # Scheduled with a delay by RetryPolicy.handle_outcome after each failure.
  # Uses the same DeliveryExecutor and RetryPolicy as DeliveryJob so retry
  # and initial-delivery paths share identical HTTP and outcome logic.
  class RetryJob < ApplicationJob
    # @param original_delivery_id [Integer] the Delivery that failed
    def perform(original_delivery_id)
      original = Delivery.find_by(id: original_delivery_id)
      return unless original

      # A new record per attempt keeps the full attempt history queryable —
      # attempt 1 got 500, attempt 2 timed out, attempt 3 succeeded.
      new_delivery = Delivery.create!(
        event: original.event,
        endpoint: original.endpoint,
        attempt_number: original.attempt_number + 1,
        scheduled_at: Time.current,
      )

      Services::DeliveryExecutor.call(new_delivery)
      Services::RetryPolicy.handle_outcome(new_delivery)
    end
  end
end
