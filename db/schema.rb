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

ActiveRecord::Schema.define(version: 20150326224247) do

  create_table "countries", force: :cascade do |t|
    t.string   "name"
    t.string   "country_code"
    t.date     "schengen_start_date"
    t.datetime "created_at",          null: false
    t.datetime "updated_at",          null: false
  end

  add_index "countries", ["country_code"], name: "index_countries_on_country_code", unique: true

  create_table "people", force: :cascade do |t|
    t.string   "first_name"
    t.string   "last_name"
    t.integer  "nationality_id"
    t.datetime "created_at",     null: false
    t.datetime "updated_at",     null: false
  end

  add_index "people", ["nationality_id"], name: "index_people_on_nationality_id"

  create_table "visits", force: :cascade do |t|
    t.date     "entry_date"
    t.date     "exit_date"
    t.integer  "schengen_days"
    t.integer  "country_id"
    t.integer  "person_id"
    t.datetime "created_at",    null: false
    t.datetime "updated_at",    null: false
  end

  add_index "visits", ["country_id"], name: "index_visits_on_country_id"
  add_index "visits", ["person_id"], name: "index_visits_on_person_id"

end
