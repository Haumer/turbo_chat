class AddCustomRoleKeyToChatMemberships < ActiveRecord::Migration[7.0]
  def change
    add_column :chat_gem_chat_memberships, :custom_role_key, :string
    add_index :chat_gem_chat_memberships, :custom_role_key
  end
end
