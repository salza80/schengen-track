# encoding: UTF-8
# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 20171123010300) do

  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "continents", force: :cascade do |t|
    t.string   "continent_code"
    t.string   "name"
    t.datetime "created_at",     null: false
    t.datetime "updated_at",     null: false
  end

  add_index "continents", ["continent_code"], name: "index_continents_on_continent_code", unique: true, using: :btree

  create_table "countries", force: :cascade do |t|
    t.string   "name"
    t.string   "country_code"
    t.date     "schengen_start_date"
    t.datetime "created_at",             null: false
    t.datetime "updated_at",             null: false
    t.integer  "continent_id"
    t.boolean  "EU_member_state"
    t.string   "visa_required"
    t.boolean  "old_schengen_calc"
    t.boolean  "additional_visa_waiver"
    t.text     "affiliate_booking_html"
    t.string   "nationality"
  end

  add_index "countries", ["continent_id"], name: "index_countries_on_continent_id", using: :btree
  add_index "countries", ["country_code"], name: "index_countries_on_country_code", unique: true, using: :btree

  create_table "users", force: :cascade do |t|
    t.string   "email",                  default: "",    null: false
    t.string   "encrypted_password",     default: "",    null: false
    t.string   "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.integer  "sign_in_count",          default: 0,     null: false
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.string   "current_sign_in_ip"
    t.string   "last_sign_in_ip"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.boolean  "guest",                  default: false, null: false
    t.string   "provider"
    t.string   "uid"
    t.string   "first_name"
    t.string   "last_name"
    t.integer  "nationality_id"
  end

  add_index "users", ["email"], name: "index_users_on_email", unique: true, using: :btree
  add_index "users", ["nationality_id"], name: "index_users_on_nationality_id", using: :btree
  add_index "users", ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true, using: :btree

  create_table "visas", force: :cascade do |t|
    t.date     "start_date"
    t.date     "end_date"
    t.integer  "no_entries"
    t.text     "visa_type"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer  "user_id"
  end

  create_table "visits", force: :cascade do |t|
    t.date     "entry_date"
    t.date     "exit_date"
    t.integer  "country_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer  "user_id"
  end

  add_index "visits", ["country_id"], name: "index_visits_on_country_id", using: :btree

  add_foreign_key "countries", "continents"
  add_foreign_key "visas", "users"
  add_foreign_key "visits", "countries"
  add_foreign_key "visits", "users"
end
