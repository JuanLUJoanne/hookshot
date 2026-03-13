# frozen_string_literal: true

require_relative "lib/hookshot/version"

Gem::Specification.new do |spec|
  spec.name        = "hookshot"
  spec.version     = Hookshot::VERSION
  spec.authors     = ["Juan Lu"]
  spec.email       = ["juanlujoanne@gmail.com"]
  spec.homepage    = "https://github.com/juanlujoanne/hookshot"
  spec.summary     = "Production-grade webhook delivery engine for Rails"
  spec.description = "A mountable Rails Engine providing reliable webhook delivery with " \
                     "automatic retries, exponential backoff, circuit breakers, idempotency, " \
                     "dead letter queues, and a real-time Hotwire dashboard."
  spec.license     = "MIT"

  spec.metadata["homepage_uri"]          = spec.homepage
  spec.metadata["source_code_uri"]       = "https://github.com/juanlujoanne/hookshot"
  spec.metadata["changelog_uri"]         = "https://github.com/juanlujoanne/hookshot/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib,docs}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  end

  spec.required_ruby_version = ">= 3.3"

  spec.add_dependency "rails", ">= 8.0"
  spec.add_dependency "solid_queue", ">= 1.0"
end
