# frozen_string_literal: true

class CreateHookshotSubscriptions < ActiveRecord::Migration[8.0]
  def change
    create_table :hookshot_subscriptions do |t|
      t.references :endpoint, null: false, foreign_key: { to_table: :hookshot_endpoints }
      t.string :event_type, null: false
      t.timestamps

      t.index %i[endpoint_id event_type], unique: true
    end
  end
end
