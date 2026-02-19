class AddInvitationAcceptedToChatGemChatMemberships < ActiveRecord::Migration[7.0]
  def change
    add_column :chat_gem_chat_memberships, :invitation_accepted, :boolean, null: false, default: true
  end
end
