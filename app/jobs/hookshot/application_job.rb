# frozen_string_literal: true

module Hookshot
  class ApplicationJob < ActiveJob::Base
    queue_as { Hookshot.configuration.queue_name }
  end
end
