# frozen_string_literal: true

# Disable all real HTTP requests in tests. All external HTTP must be stubbed.
# Use stub_request(:post, url).to_return(...) or .to_timeout or .to_raise(...)
WebMock.disable_net_connect!(allow_localhost: true)
