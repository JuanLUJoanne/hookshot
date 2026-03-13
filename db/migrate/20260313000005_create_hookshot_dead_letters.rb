# frozen_string_literal: true

class CreateHookshotDeadLetters < ActiveRecord::Migration[8.0]
  def change
    create_table :hookshot_dead_letters do |t|
      t.references :delivery, null: false, foreign_key: { to_table: :hookshot_deliveries }
      t.references :event, null: false, foreign_key: { to_table: :hookshot_events }
      t.references :endpoint, null: false, foreign_key: { to_table: :hookshot_endpoints }
      t.integer  :reason, null: false, default: 0 # enum: max_retries_exceeded(0), circuit_open(1), manual(2)
      t.integer  :total_attempts
      t.datetime :last_attempted_at
      t.timestamps

      t.index :reason
    end
  end
end
