# frozen_string_literal: true

module Hookshot
  class Engine < ::Rails::Engine
    isolate_namespace Hookshot

    # Expose engine migrations to the host app.
    # Host apps run: rails hookshot:install:migrations && rails db:migrate
    initializer "hookshot.migrations" do
      config.paths["db/migrate"].expanded.each do |path|
        Rails.application.config.paths["db/migrate"] << path
      end
    end
  end
end
