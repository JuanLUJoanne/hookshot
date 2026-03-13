# frozen_string_literal: true

module Hookshot
  # Holds all configuration for the Hookshot engine.
  # Set values in config/initializers/hookshot.rb via Hookshot.configure.
  class Configuration
    # @return [Integer] maximum delivery attempts before moving to dead letter queue
    attr_accessor :max_retries

    # @return [Integer] base delay in seconds for the first retry
    attr_accessor :retry_base_delay

    # @return [Integer] maximum delay in seconds between retries (caps exponential growth)
    attr_accessor :retry_max_delay

    # @return [Integer] maximum random jitter added to retry delay, in seconds
    attr_accessor :jitter_max

    # @return [Symbol] HMAC algorithm to use for signing (:sha256)
    attr_accessor :signature_algorithm

    # @return [Symbol] Active Job queue name for delivery jobs
    attr_accessor :queue_name

    # @return [Integer] HTTP connect timeout in seconds
    attr_accessor :connect_timeout

    # @return [Integer] HTTP read timeout in seconds
    attr_accessor :read_timeout

    def initialize
      @max_retries        = 8
      @retry_base_delay   = 15      # seconds
      @retry_max_delay    = 3_600   # 1 hour cap
      @jitter_max         = 5       # seconds of random jitter
      @signature_algorithm = :sha256
      @queue_name         = :webhooks
      @connect_timeout    = 5       # seconds
      @read_timeout       = 10      # seconds
    end
  end
end
