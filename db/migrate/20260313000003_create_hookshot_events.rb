# frozen_string_literal: true

class CreateHookshotEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :hookshot_events do |t|
      t.string  :event_type, null: false
      t.string  :idempotency_key, null: false
      t.jsonb   :payload, null: false, default: {}
      t.integer :status, null: false, default: 0 # enum: pending(0), dispatched(1), completed(2), failed(3)
      t.timestamps

      t.index :idempotency_key, unique: true
      t.index :event_type
      t.index :status
    end
  end
end
