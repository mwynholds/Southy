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

ActiveRecord::Schema.define(version: 2019_08_07_211604) do

  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "bounds", force: :cascade do |t|
    t.datetime "departure_time", null: false
    t.string "departure_code", null: false
    t.datetime "arrival_time", null: false
    t.string "arrival_code", null: false
    t.string "flights", default: [], array: true
    t.bigint "reservation_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "departure_city"
    t.string "departure_state"
    t.string "arrival_city"
    t.string "arrival_state"
    t.string "bound_type"
    t.index ["reservation_id"], name: "index_bounds_on_reservation_id"
  end

  create_table "passengers", force: :cascade do |t|
    t.string "name", null: false
    t.bigint "reservation_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["reservation_id"], name: "index_passengers_on_reservation_id"
  end

  create_table "reservations", force: :cascade do |t|
    t.string "confirmation_number", null: false
    t.string "origin_code", null: false
    t.string "destination_code", null: false
    t.string "email"
    t.datetime "last_checkin_attempt"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "created_by"
  end

  create_table "seats", force: :cascade do |t|
    t.string "group", null: false
    t.string "position", null: false
    t.string "flight", null: false
    t.bigint "bound_id"
    t.bigint "passenger_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bound_id"], name: "index_seats_on_bound_id"
    t.index ["passenger_id"], name: "index_seats_on_passenger_id"
  end

  create_table "stops", force: :cascade do |t|
    t.string "code", null: false
    t.datetime "arrival_time", null: false
    t.datetime "departure_time", null: false
    t.bigint "bound_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "city"
    t.string "state"
    t.boolean "plane_change", default: true
    t.index ["bound_id"], name: "index_stops_on_bound_id"
  end

end
