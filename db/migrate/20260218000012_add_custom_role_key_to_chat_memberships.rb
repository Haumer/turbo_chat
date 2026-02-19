class AddCustomRoleKeyToChatMemberships < ActiveRecord::Migration[7.0]
  def change
    add_column :turbo_chat_chat_memberships, :custom_role_key, :string
    add_index :turbo_chat_chat_memberships, :custom_role_key
  end
end
