class AddChatModeToTurboChatChats < ActiveRecord::Migration[7.0]
  def change
    add_column :turbo_chat_chats, :chat_mode, :integer, null: false, default: 0
    add_index :turbo_chat_chats, :chat_mode
  end
end
