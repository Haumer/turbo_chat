class CreateTurboChatChatMemberships < ActiveRecord::Migration[7.0]
  def change
    create_table :turbo_chat_chat_memberships do |t|
      t.references :chat, null: false, foreign_key: { to_table: :turbo_chat_chats }
      t.references :participant, polymorphic: true, null: false
      t.integer :role, null: false, default: 0
      t.boolean :muted, null: false, default: false
      t.datetime :timed_out_until
      t.datetime :removed_at
      t.timestamps
    end

    add_index :turbo_chat_chat_memberships,
              %i[chat_id participant_type participant_id],
              unique: true,
              where: "removed_at IS NULL",
              name: "index_turbo_chat_memberships_on_chat_participant_active"
  end
end
