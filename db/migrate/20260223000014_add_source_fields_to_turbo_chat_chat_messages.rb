class AddSourceFieldsToTurboChatChatMessages < ActiveRecord::Migration[7.0]
  def change
    add_column :turbo_chat_chat_messages, :source, :string, null: false, default: "app"
    add_column :turbo_chat_chat_messages, :external_id, :string
    add_column :turbo_chat_chat_messages, :sent_at, :datetime

    add_index :turbo_chat_chat_messages,
              %i[chat_id source external_id],
              unique: true,
              where: "external_id IS NOT NULL",
              name: "index_turbo_chat_messages_external_id"
  end
end
