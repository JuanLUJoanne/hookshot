# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"

require File.expand_path("dummy/config/environment", __dir__)

require "rspec/rails"
require "shoulda/matchers"
require "webmock/rspec"

# Load engine migrations into the dummy app's migration path.
# This ensures db:migrate picks up Hookshot's migrations.
ENGINE_ROOT = File.expand_path("..", __dir__)
ActiveRecord::Migration.maintain_test_schema!

# Load spec/support files
Dir[File.expand_path("support/**/*.rb", __dir__)].each { |f| require f }

RSpec.configure do |config|
  # Use database transactions for speed — rolled back after each example
  config.use_transactional_fixtures = true

  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  Shoulda::Matchers.configure do |shoulda|
    shoulda.integrate do |with|
      with.test_framework :rspec
      with.library :rails
    end
  end
end
