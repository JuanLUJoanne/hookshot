# frozen_string_literal: true

require "rails"
require "active_record/railtie"
require "active_job/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "action_cable/engine"

require "hookshot"

module Dummy
  class Application < Rails::Application
    config.load_defaults 8.0
    config.eager_load = false
    config.logger = Logger.new($stdout)
    config.log_level = :warn
  end
end
