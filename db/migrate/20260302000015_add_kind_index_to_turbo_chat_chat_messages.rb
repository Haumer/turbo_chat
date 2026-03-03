class AddKindIndexToTurboChatChatMessages < ActiveRecord::Migration[7.0]
  def change
    add_index :turbo_chat_chat_messages, %i[chat_id kind created_at],
              name: "index_turbo_chat_messages_on_chat_kind_created"
  end
end
