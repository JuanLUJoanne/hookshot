# frozen_string_literal: true

FactoryBot.define do
  factory :hookshot_subscription, class: "Hookshot::Subscription" do
    association :endpoint, factory: :hookshot_endpoint
    event_type { "order.created" }
  end
end
