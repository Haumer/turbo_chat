class AddInvitationAcceptedToTurboChatChatMemberships < ActiveRecord::Migration[7.0]
  def change
    add_column :turbo_chat_chat_memberships, :invitation_accepted, :boolean, null: false, default: true
  end
end
