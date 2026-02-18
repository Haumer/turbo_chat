class CreateChatGemChats < ActiveRecord::Migration[7.0]
  def change
    create_table :chat_gem_chats do |t|
      t.string :title, null: false
      t.timestamps
    end
  end
end
