# frozen_string_literal: true

FactoryBot.define do
  factory :hookshot_delivery, class: "Hookshot::Delivery" do
    association :event, factory: :hookshot_event
    association :endpoint, factory: :hookshot_endpoint
    attempt_number { 1 }
    status { :pending }
    idempotency_key { SecureRandom.uuid }

    trait :success do
      status { :success }
      response_status { 200 }
      response_body { '{"ok":true}' }
      duration_ms { 143 }
      delivered_at { Time.current }
    end

    trait :failed do
      status { :failed }
      response_status { 503 }
      response_body { "Service Unavailable" }
      duration_ms { 201 }
    end

    trait :timed_out do
      status { :failed }
      error_message { "execution expired" }
      duration_ms { 30_000 }
    end

    trait :circuit_open do
      status { :circuit_open }
    end

    trait :retried do
      attempt_number { 2 }
      scheduled_at { 30.seconds.from_now }
    end
  end
end
