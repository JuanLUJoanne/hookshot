# frozen_string_literal: true

module Hookshot
  # Represents an endpoint's subscription to a specific event type.
  #
  # Event types use dot-separated lowercase identifiers (e.g. "order.created").
  # An endpoint may subscribe to multiple event types, but not the same one twice.
  class Subscription < ApplicationRecord
    belongs_to :endpoint, class_name: "Hookshot::Endpoint"

    EVENT_TYPE_FORMAT = /\A[a-z_]+(\.[a-z_]+)*\z/

    validates :event_type, presence: true,
                           format: {
                             with: EVENT_TYPE_FORMAT,
                             message: 'must be lowercase words separated by dots (e.g. "order.created")',
                           },
                           uniqueness: { scope: :endpoint_id }
  end
end
