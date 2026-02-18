class CreateChatGemChatMessages < ActiveRecord::Migration[7.0]
  def change
    create_table :chat_gem_chat_messages do |t|
      t.references :chat, null: false, foreign_key: { to_table: :chat_gem_chats }
      t.references :participant, polymorphic: true, null: false
      t.text :body
      t.integer :kind, null: false, default: 0
      t.integer :signal_type
      t.timestamps
    end

    add_index :chat_gem_chat_messages, %i[chat_id created_at id], name: "index_chat_gem_messages_order"
  end
end
