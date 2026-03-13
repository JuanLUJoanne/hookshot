# frozen_string_literal: true

# factory_bot_rails Railtie calls find_definitions during app init with the
# default path, which resolves relative to Dir.pwd (spec/dummy after chdir).
# Override with an absolute path and re-run find_definitions so factories
# in spec/factories/ are registered.
FactoryBot.definition_file_paths = [File.expand_path("../factories", __dir__)]
FactoryBot.find_definitions

RSpec.configure do |config|
  config.include FactoryBot::Syntax::Methods
end
