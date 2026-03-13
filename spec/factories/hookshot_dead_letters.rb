# frozen_string_literal: true

FactoryBot.define do
  factory :hookshot_dead_letter, class: "Hookshot::DeadLetter" do
    association :delivery, factory: :hookshot_delivery
    reason { :max_retries_exceeded }
    total_attempts { 8 }
    last_attempted_at { Time.current }

    # Derive event and endpoint from the delivery to keep records consistent.
    # Override explicitly in specs that need different associations.
    after(:build) do |dead_letter|
      dead_letter.event    ||= dead_letter.delivery.event
      dead_letter.endpoint ||= dead_letter.delivery.endpoint
    end

    trait :circuit_open do
      reason { :circuit_open }
      total_attempts { 1 }
    end

    trait :manual do
      reason { :manual }
    end
  end
end
