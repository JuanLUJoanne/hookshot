# frozen_string_literal: true

module Hookshot
  module Services
    # Encapsulates retry strategy and dead-letter decisions.
    #
    # Exponential backoff with jitter (ADR-003):
    #   delay = base_delay * (2^attempt) + rand(0..jitter_max)
    #           capped at retry_max_delay
    #
    # Without jitter, a fleet of failing endpoints retried at the same moment
    # creates a thundering-herd against the same receiver. Jitter spreads those
    # retries across a window, smoothing load on both sides.
    class RetryPolicy
      # Determine whether a failed delivery should be retried or dead-lettered.
      #
      # @param delivery [Hookshot::Delivery]
      # @return [:retry, :dead_letter]
      def self.outcome(delivery)
        delivery.attempt_number >= Hookshot.configuration.max_retries ? :dead_letter : :retry
      end

      # Seconds to wait before the next delivery attempt.
      #
      # @param attempt_number [Integer] the attempt that just failed (1-based)
      # @return [Integer] seconds
      def self.next_delay(attempt_number)
        config = Hookshot.configuration
        base   = config.retry_base_delay * (2**attempt_number)
        jitter = rand(0..config.jitter_max)
        [base + jitter, config.retry_max_delay].min
      end

      # Post-delivery hook shared by DeliveryJob and RetryJob.
      # Schedules a retry or creates a DeadLetter depending on attempt count.
      #
      # @param delivery [Hookshot::Delivery]
      # @return [void]
      def self.handle_outcome(delivery)
        # Success or circuit_open are handled upstream; nothing to do here.
        return unless delivery.status_failed?

        case outcome(delivery)
        when :retry
          Hookshot::RetryJob.set(wait: next_delay(delivery.attempt_number).seconds)
                            .perform_later(delivery.id)
        when :dead_letter
          move_to_dead_letter(delivery)
        end
      end

      # @api private
      def self.move_to_dead_letter(delivery)
        DeadLetter.create!(
          delivery:,
          event: delivery.event,
          endpoint: delivery.endpoint,
          reason: :max_retries_exceeded,
          total_attempts: delivery.attempt_number,
          last_attempted_at: Time.current,
        )
        delivery.event.status_failed!
      end

      private_class_method :move_to_dead_letter
    end
  end
end
