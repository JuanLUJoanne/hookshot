# frozen_string_literal: true

class CreateHookshotDeliveries < ActiveRecord::Migration[8.0]
  def change
    create_table :hookshot_deliveries do |t|
      t.references :event, null: false, foreign_key: { to_table: :hookshot_events }
      t.references :endpoint, null: false, foreign_key: { to_table: :hookshot_endpoints }
      t.integer  :attempt_number, null: false, default: 1
      t.integer  :status, null: false, default: 0 # enum: pending(0), success(1), failed(2), circuit_open(3)
      t.integer  :response_status
      t.text     :response_body
      t.jsonb    :response_headers, null: false, default: {}
      t.jsonb    :request_headers, null: false, default: {}
      t.integer  :duration_ms
      t.string   :error_message
      t.string   :idempotency_key, null: false
      t.datetime :scheduled_at
      t.datetime :delivered_at
      t.timestamps

      t.index %i[event_id endpoint_id]
      t.index :status
      t.index :idempotency_key, unique: true
      t.index :scheduled_at
    end
  end
end
