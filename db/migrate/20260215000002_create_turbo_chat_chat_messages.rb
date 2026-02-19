class CreateTurboChatChatMessages < ActiveRecord::Migration[7.0]
  def change
    create_table :turbo_chat_chat_messages do |t|
      t.references :chat, null: false, foreign_key: { to_table: :turbo_chat_chats }
      t.references :participant, polymorphic: true, null: false
      t.text :body
      t.integer :kind, null: false, default: 0
      t.integer :signal_type
      t.timestamps
    end

    add_index :turbo_chat_chat_messages, %i[chat_id created_at id], name: "index_turbo_chat_messages_order"
  end
end
