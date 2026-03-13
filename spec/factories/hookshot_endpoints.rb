# frozen_string_literal: true

FactoryBot.define do
  factory :hookshot_endpoint, class: "Hookshot::Endpoint" do
    # Unique URL per factory call prevents uniqueness collisions across specs
    url { "https://example.com/webhooks/#{SecureRandom.hex(4)}" }
    secret { SecureRandom.hex(32) }
    status { :active }
    consecutive_failures { 0 }
    metadata { {} }

    trait :paused do
      status { :paused }
    end

    trait :circuit_open do
      status { :circuit_open }
      consecutive_failures { 5 }
      circuit_opened_at { 1.minute.ago }
    end
  end
end
