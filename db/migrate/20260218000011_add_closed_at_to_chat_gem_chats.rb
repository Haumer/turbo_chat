class AddClosedAtToChatGemChats < ActiveRecord::Migration[7.0]
  def change
    add_column :chat_gem_chats, :closed_at, :datetime
    add_index :chat_gem_chats, :closed_at
  end
end
