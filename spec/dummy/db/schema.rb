# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_03_13_000005) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "hookshot_dead_letters", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "delivery_id", null: false
    t.bigint "endpoint_id", null: false
    t.bigint "event_id", null: false
    t.datetime "last_attempted_at"
    t.integer "reason", default: 0, null: false
    t.integer "total_attempts"
    t.datetime "updated_at", null: false
    t.index ["delivery_id"], name: "index_hookshot_dead_letters_on_delivery_id"
    t.index ["endpoint_id"], name: "index_hookshot_dead_letters_on_endpoint_id"
    t.index ["event_id"], name: "index_hookshot_dead_letters_on_event_id"
    t.index ["reason"], name: "index_hookshot_dead_letters_on_reason"
  end

  create_table "hookshot_deliveries", force: :cascade do |t|
    t.integer "attempt_number", default: 1, null: false
    t.datetime "created_at", null: false
    t.datetime "delivered_at"
    t.integer "duration_ms"
    t.bigint "endpoint_id", null: false
    t.string "error_message"
    t.bigint "event_id", null: false
    t.string "idempotency_key", null: false
    t.jsonb "request_headers", default: {}, null: false
    t.text "response_body"
    t.jsonb "response_headers", default: {}, null: false
    t.integer "response_status"
    t.datetime "scheduled_at"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["endpoint_id"], name: "index_hookshot_deliveries_on_endpoint_id"
    t.index ["event_id", "endpoint_id"], name: "index_hookshot_deliveries_on_event_id_and_endpoint_id"
    t.index ["event_id"], name: "index_hookshot_deliveries_on_event_id"
    t.index ["idempotency_key"], name: "index_hookshot_deliveries_on_idempotency_key", unique: true
    t.index ["scheduled_at"], name: "index_hookshot_deliveries_on_scheduled_at"
    t.index ["status"], name: "index_hookshot_deliveries_on_status"
  end

  create_table "hookshot_endpoints", force: :cascade do |t|
    t.datetime "circuit_opened_at"
    t.integer "consecutive_failures", default: 0, null: false
    t.datetime "created_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "secret", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.index ["status"], name: "index_hookshot_endpoints_on_status"
    t.index ["url"], name: "index_hookshot_endpoints_on_url", unique: true
  end

  create_table "hookshot_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "event_type", null: false
    t.string "idempotency_key", null: false
    t.jsonb "payload", default: {}, null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["event_type"], name: "index_hookshot_events_on_event_type"
    t.index ["idempotency_key"], name: "index_hookshot_events_on_idempotency_key", unique: true
    t.index ["status"], name: "index_hookshot_events_on_status"
  end

  create_table "hookshot_subscriptions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "endpoint_id", null: false
    t.string "event_type", null: false
    t.datetime "updated_at", null: false
    t.index ["endpoint_id", "event_type"], name: "index_hookshot_subscriptions_on_endpoint_id_and_event_type", unique: true
    t.index ["endpoint_id"], name: "index_hookshot_subscriptions_on_endpoint_id"
  end

  add_foreign_key "hookshot_dead_letters", "hookshot_deliveries", column: "delivery_id"
  add_foreign_key "hookshot_dead_letters", "hookshot_endpoints", column: "endpoint_id"
  add_foreign_key "hookshot_dead_letters", "hookshot_events", column: "event_id"
  add_foreign_key "hookshot_deliveries", "hookshot_endpoints", column: "endpoint_id"
  add_foreign_key "hookshot_deliveries", "hookshot_events", column: "event_id"
  add_foreign_key "hookshot_subscriptions", "hookshot_endpoints", column: "endpoint_id"
end
