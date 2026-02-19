class AddClosedAtToTurboChatChats < ActiveRecord::Migration[7.0]
  def change
    add_column :turbo_chat_chats, :closed_at, :datetime
    add_index :turbo_chat_chats, :closed_at
  end
end
