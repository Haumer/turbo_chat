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

ActiveRecord::Schema[7.1].define(version: 2026_02_18_000013) do
  create_table "chat_gem_chat_memberships", force: :cascade do |t|
    t.integer "chat_id", null: false
    t.string "participant_type", null: false
    t.integer "participant_id", null: false
    t.integer "role", default: 0, null: false
    t.boolean "muted", default: false, null: false
    t.datetime "timed_out_until"
    t.datetime "removed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "custom_role_key"
    t.boolean "invitation_accepted", default: true, null: false
    t.index ["chat_id", "participant_type", "participant_id"], name: "index_chat_gem_memberships_on_chat_participant_active", unique: true, where: "removed_at IS NULL"
    t.index ["chat_id"], name: "index_chat_gem_chat_memberships_on_chat_id"
    t.index ["custom_role_key"], name: "index_chat_gem_chat_memberships_on_custom_role_key"
    t.index ["participant_type", "participant_id"], name: "index_chat_gem_chat_memberships_on_participant"
  end

  create_table "chat_gem_chat_messages", force: :cascade do |t|
    t.integer "chat_id", null: false
    t.string "participant_type", null: false
    t.integer "participant_id", null: false
    t.text "body"
    t.integer "kind", default: 0, null: false
    t.integer "signal_type"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["chat_id", "created_at", "id"], name: "index_chat_gem_messages_order"
    t.index ["chat_id"], name: "index_chat_gem_chat_messages_on_chat_id"
    t.index ["participant_type", "participant_id"], name: "index_chat_gem_chat_messages_on_participant"
  end

  create_table "chat_gem_chats", force: :cascade do |t|
    t.string "title", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "closed_at"
    t.index ["closed_at"], name: "index_chat_gem_chats_on_closed_at"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "chat_gem_chat_memberships", "chat_gem_chats", column: "chat_id"
  add_foreign_key "chat_gem_chat_messages", "chat_gem_chats", column: "chat_id"
end
