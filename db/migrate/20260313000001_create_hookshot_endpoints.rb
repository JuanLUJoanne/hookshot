# frozen_string_literal: true

class CreateHookshotEndpoints < ActiveRecord::Migration[8.0]
  def change
    create_table :hookshot_endpoints do |t|
      t.string  :url, null: false
      t.string  :secret, null: false
      t.integer :status, null: false, default: 0 # enum: active(0), paused(1), circuit_open(2)
      t.integer :consecutive_failures, null: false, default: 0
      t.datetime :circuit_opened_at
      t.jsonb :metadata, null: false, default: {}
      t.timestamps

      t.index :url, unique: true
      t.index :status
    end
  end
end
