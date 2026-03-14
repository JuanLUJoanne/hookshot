# frozen_string_literal: true

require "hookshot/version"
require "hookshot/engine"

module Hookshot
  class << self
    # Yields the configuration object for setup in an initializer.
    #
    # @example
    #   Hookshot.configure do |config|
    #     config.max_retries = 8
    #   end
    #
    # @yieldparam config [Hookshot::Configuration]
    def configure
      yield configuration
    end

    # Returns the current configuration, initializing with defaults if needed.
    #
    # @return [Hookshot::Configuration]
    def configuration
      @configuration ||= Configuration.new
    end

    # Resets configuration to defaults. Primarily used in test suites.
    #
    # @return [void]
    def reset_configuration!
      @configuration = Configuration.new
    end

    # Triggers a webhook event, fanning out to all subscribed endpoints.
    #
    # @param event_type [String] the event name (e.g. "order.created")
    # @param payload [Hash] the event data to deliver
    # @param idempotency_key [String, nil] optional; auto-generated UUID if omitted
    # @return [Hookshot::Event] the created event record
    def trigger(event_type, payload:, idempotency_key: nil)
      Services::EventDispatcher.call(event_type:, payload:, idempotency_key:)
    end
  end
end

# Services are plain Ruby — required explicitly rather than autoloaded.
# They live in lib/ because they are engine internals, not host-app components.
require "hookshot/configuration"
require "hookshot/services/signature_generator"
require "hookshot/services/signature_verifier"
# Uncommented as each service is implemented:
require "hookshot/services/retry_policy"
require "hookshot/services/delivery_executor"
require "hookshot/services/event_dispatcher"
