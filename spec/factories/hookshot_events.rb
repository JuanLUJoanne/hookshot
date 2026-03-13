# frozen_string_literal: true

FactoryBot.define do
  factory :hookshot_event, class: "Hookshot::Event" do
    event_type { "order.created" }
    idempotency_key { SecureRandom.uuid }
    payload { { order_id: 1, total: "99.99" } }
    status { :pending }

    trait :dispatched do
      status { :dispatched }
    end

    trait :completed do
      status { :completed }
    end

    trait :failed do
      status { :failed }
    end
  end
end
