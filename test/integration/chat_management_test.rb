require_relative "../test_helper"

class ChatManagementTest < ActionDispatch::IntegrationTest
  teardown do
    TurboChat::ChatMessage.delete_all
    TurboChat::ChatMembership.delete_all
    TurboChat::Chat.delete_all
    User.delete_all
  end

  test "admin can invite participant to chat" do
    admin = User.create!(email: "invite-admin@example.com")
    invitee = User.create!(email: "invite-target@example.com")
    chat = TurboChat::Chat.create!(title: "Invite Chat")
    TurboChat::ChatMembership.create!(chat: chat, participant: admin, role: :admin)

    with_current_chat_participant(admin) do
      post "/chat/chats/#{chat.id}/chat_memberships", params: {
        chat_membership: {
          participant_type: "User",
          participant_id: invitee.id
        }
      }
    end

    assert_redirected_to "/chat/chats/#{chat.id}"
    invited_membership = TurboChat::ChatMembership.find_by!(chat: chat, participant: invitee)
    assert invited_membership.pending?
    assert_not invited_membership.active?
    system_message = TurboChat::ChatMessage.where(chat: chat, kind: :system).order(id: :desc).first
    assert_equal "#{admin.email} invited #{invitee.email}.", system_message&.body
  end

  test "inviting participant includes lifecycle event payload when enabled" do
    previous_emit_chat_lifecycle_events = TurboChat.configuration.emit_chat_lifecycle_events
    TurboChat.configuration.emit_chat_lifecycle_events = true

    admin = User.create!(email: "invite-event-admin@example.com")
    invitee = User.create!(email: "invite-event-target@example.com")
    chat = TurboChat::Chat.create!(title: "Invite Event Chat")
    TurboChat::ChatMembership.create!(chat: chat, participant: admin, role: :admin)

    with_current_chat_participant(admin) do
      post "/chat/chats/#{chat.id}/chat_memberships", params: {
        chat_membership: {
          participant_type: "User",
          participant_id: invitee.id
        }
      }
      assert_redirected_to "/chat/chats/#{chat.id}"
      follow_redirect!
      assert_response :success
    end

    assert_includes response.body, %(data-chat-emit-chat-lifecycle-events="true")
    assert_includes response.body, %(data-chat-lifecycle-event="{&quot;eventName&quot;:&quot;turbo-chat:chat-invited&quot;)
  ensure
    TurboChat.configuration.emit_chat_lifecycle_events = previous_emit_chat_lifecycle_events
  end

  test "member cannot invite participant to chat" do
    member = User.create!(email: "invite-member@example.com")
    invitee = User.create!(email: "invite-blocked@example.com")
    chat = TurboChat::Chat.create!(title: "Invite Forbidden")
    TurboChat::ChatMembership.create!(chat: chat, participant: member, role: :member)

    with_current_chat_participant(member) do
      post "/chat/chats/#{chat.id}/chat_memberships", params: {
        chat_membership: {
          participant_type: "User",
          participant_id: invitee.id
        }
      }
    end

    assert_response :forbidden
    assert_not TurboChat::ChatMembership.active.exists?(chat: chat, participant: invitee)
  end

  test "admin can update another member role" do
    admin = User.create!(email: "role-admin@example.com")
    member = User.create!(email: "role-member@example.com")
    chat = TurboChat::Chat.create!(title: "Role Management")
    TurboChat::ChatMembership.create!(chat: chat, participant: admin, role: :admin)
    member_membership = TurboChat::ChatMembership.create!(chat: chat, participant: member, role: :member)

    with_current_chat_participant(admin) do
      patch "/chat/chats/#{chat.id}/chat_memberships/#{member_membership.id}", params: {
        chat_membership: {
          role_key: "moderator"
        }
      }
    end

    assert_redirected_to "/chat/chats/#{chat.id}"
    assert member_membership.reload.moderator?
  end

  test "member cannot update another member role" do
    member = User.create!(email: "role-forbidden-member@example.com")
    target = User.create!(email: "role-forbidden-target@example.com")
    chat = TurboChat::Chat.create!(title: "Role Forbidden")
    TurboChat::ChatMembership.create!(chat: chat, participant: member, role: :member)
    target_membership = TurboChat::ChatMembership.create!(chat: chat, participant: target, role: :member)

    with_current_chat_participant(member) do
      patch "/chat/chats/#{chat.id}/chat_memberships/#{target_membership.id}", params: {
        chat_membership: {
          role_key: "moderator"
        }
      }
    end

    assert_response :forbidden
    assert target_membership.reload.member?
  end

  test "admin cannot assign role with higher rank than self" do
    config = TurboChat.configuration
    config.add_role(:super_admin, name: "Super Admin", rank: 5, permissions: %i[view_chat post_message])

    admin = User.create!(email: "role-rank-admin@example.com")
    target = User.create!(email: "role-rank-target@example.com")
    chat = TurboChat::Chat.create!(title: "Role Rank Guard")
    TurboChat::ChatMembership.create!(chat: chat, participant: admin, role: :admin)
    target_membership = TurboChat::ChatMembership.create!(chat: chat, participant: target, role: :member)

    with_current_chat_participant(admin) do
      patch "/chat/chats/#{chat.id}/chat_memberships/#{target_membership.id}", params: {
        chat_membership: {
          role_key: "super_admin"
        }
      }
    end

    assert_redirected_to "/chat/chats/#{chat.id}"
    assert target_membership.reload.member?
  ensure
    config.remove_role(:super_admin)
  end

  test "admin cannot invite participant with mismatched participant type" do
    admin = User.create!(email: "invite-admin-type-check@example.com")
    chat = TurboChat::Chat.create!(title: "Invite Type Check")
    TurboChat::ChatMembership.create!(chat: chat, participant: admin, role: :admin)

    klass_name = "TurboChatInviteExternalUser"
    Object.send(:remove_const, klass_name) if Object.const_defined?(klass_name)

    external_participant_class = Class.new(ApplicationRecord) do
      self.table_name = "users"
      acts_as_chat_participant
    end
    Object.const_set(klass_name, external_participant_class)
    external_participant = external_participant_class.create!(email: "invite-external@example.com")

    with_current_chat_participant(admin) do
      post "/chat/chats/#{chat.id}/chat_memberships", params: {
        chat_membership: {
          participant_type: klass_name,
          participant_id: external_participant.id
        }
      }
    end

    assert_redirected_to "/chat/chats/#{chat.id}"
    assert_not TurboChat::ChatMembership.active.exists?(
      chat: chat,
      participant_type: klass_name,
      participant_id: external_participant.id
    )
  ensure
    Object.send(:remove_const, klass_name) if defined?(klass_name) && Object.const_defined?(klass_name)
  end

  test "participant can leave chat" do
    participant = User.create!(email: "leave-user@example.com")
    chat = TurboChat::Chat.create!(title: "Leave Chat")
    membership = TurboChat::ChatMembership.create!(chat: chat, participant: participant, role: :member)

    with_current_chat_participant(participant) do
      patch "/chat/chats/#{chat.id}/leave"
    end

    assert_redirected_to "/chat/chats"
    assert membership.reload.removed_at.present?
  end

  test "leaving chat includes lifecycle event payload when enabled" do
    previous_emit_chat_lifecycle_events = TurboChat.configuration.emit_chat_lifecycle_events
    TurboChat.configuration.emit_chat_lifecycle_events = true

    participant = User.create!(email: "leave-event-user@example.com")
    chat = TurboChat::Chat.create!(title: "Leave Event Chat")
    TurboChat::ChatMembership.create!(chat: chat, participant: participant, role: :member)

    with_current_chat_participant(participant) do
      patch "/chat/chats/#{chat.id}/leave"
      assert_redirected_to "/chat/chats"
      follow_redirect!
      assert_response :success
    end

    assert_includes response.body, %(data-chat-emit-chat-lifecycle-events="true")
    assert_includes response.body, %(data-chat-lifecycle-event="{&quot;eventName&quot;:&quot;turbo-chat:chat-left&quot;)
  ensure
    TurboChat.configuration.emit_chat_lifecycle_events = previous_emit_chat_lifecycle_events
  end

  test "invited participant can accept invitation from chats index" do
    admin = User.create!(email: "accept-admin@example.com")
    invitee = User.create!(email: "accept-invitee@example.com")
    chat = TurboChat::Chat.create!(title: "Accept Invite Chat")
    TurboChat::ChatMembership.create!(chat: chat, participant: admin, role: :admin)
    invited_membership = TurboChat::ChatMembership.create!(
      chat: chat,
      participant: invitee,
      role: :member,
      invitation_accepted: false
    )

    with_current_chat_participant(invitee) do
      get "/chat/chats"
      assert_response :success
      assert_includes response.body, "Pending Invitations"
      assert_includes response.body, "Accept"
      assert_includes response.body, "Decline"

      patch "/chat/chats/#{chat.id}/accept"
      assert_redirected_to "/chat/chats"
    end

    assert invited_membership.reload.active?
    assert invited_membership.invitation_accepted?
    system_message = TurboChat::ChatMessage.where(chat: chat, kind: :system).order(id: :desc).first
    assert_equal "#{invitee.email} accepted the invitation.", system_message&.body
  end

  test "accepting invitation includes frontend event payload when enabled" do
    previous_emit_invitation_events = TurboChat.configuration.emit_invitation_events
    TurboChat.configuration.emit_invitation_events = true

    invitee = User.create!(email: "accept-event-invitee@example.com")
    chat = TurboChat::Chat.create!(title: "Accept Event Chat")
    TurboChat::ChatMembership.create!(
      chat: chat,
      participant: invitee,
      role: :member,
      invitation_accepted: false
    )

    with_current_chat_participant(invitee) do
      patch "/chat/chats/#{chat.id}/accept"
      assert_redirected_to "/chat/chats"
      follow_redirect!
      assert_response :success
    end

    assert_includes response.body, %(data-chat-emit-invitation-events="true")
    assert_includes response.body, %(data-chat-invitation-accepted="{&quot;chatId&quot;:&quot;#{chat.id}&quot;)
  ensure
    TurboChat.configuration.emit_invitation_events = previous_emit_invitation_events
  end

  test "accepting invitation includes lifecycle event payload when enabled" do
    previous_emit_chat_lifecycle_events = TurboChat.configuration.emit_chat_lifecycle_events
    TurboChat.configuration.emit_chat_lifecycle_events = true

    invitee = User.create!(email: "accept-lifecycle-invitee@example.com")
    chat = TurboChat::Chat.create!(title: "Accept Lifecycle Chat")
    TurboChat::ChatMembership.create!(
      chat: chat,
      participant: invitee,
      role: :member,
      invitation_accepted: false
    )

    with_current_chat_participant(invitee) do
      patch "/chat/chats/#{chat.id}/accept"
      assert_redirected_to "/chat/chats"
      follow_redirect!
      assert_response :success
    end

    assert_includes response.body, %(data-chat-emit-chat-lifecycle-events="true")
    assert_includes response.body, %(data-chat-lifecycle-event="{&quot;eventName&quot;:&quot;turbo-chat:chat-joined&quot;)
  ensure
    TurboChat.configuration.emit_chat_lifecycle_events = previous_emit_chat_lifecycle_events
  end

  test "accept redirects with migration alert when invitation tracking is unavailable" do
    invitee = User.create!(email: "accept-legacy-invitee@example.com")
    chat = TurboChat::Chat.create!(title: "Accept Legacy Chat")
    invited_membership = TurboChat::ChatMembership.create!(
      chat: chat,
      participant: invitee,
      role: :member,
      invitation_accepted: false
    )

    TurboChat::ChatMembership.stub(:invitation_tracking_supported?, false) do
      with_current_chat_participant(invitee) do
        patch "/chat/chats/#{chat.id}/accept"
        assert_redirected_to "/chat/chats"
      end
    end

    assert_not invited_membership.reload.invitation_accepted?
  end

  test "invited participant can decline invitation from chats index" do
    invitee = User.create!(email: "decline-invitee@example.com")
    chat = TurboChat::Chat.create!(title: "Decline Invite Chat")
    invited_membership = TurboChat::ChatMembership.create!(
      chat: chat,
      participant: invitee,
      role: :member,
      invitation_accepted: false
    )

    with_current_chat_participant(invitee) do
      patch "/chat/chats/#{chat.id}/decline"
      assert_redirected_to "/chat/chats"
    end

    invited_membership.reload
    assert invited_membership.removed_at.present?
    assert_not invited_membership.active?
    system_message = TurboChat::ChatMessage.where(chat: chat, kind: :system).order(id: :desc).first
    assert_equal "#{invitee.email} declined the invitation.", system_message&.body
  end

  test "declining invitation includes lifecycle event payload when enabled" do
    previous_emit_chat_lifecycle_events = TurboChat.configuration.emit_chat_lifecycle_events
    TurboChat.configuration.emit_chat_lifecycle_events = true

    invitee = User.create!(email: "decline-event-invitee@example.com")
    chat = TurboChat::Chat.create!(title: "Decline Event Chat")
    TurboChat::ChatMembership.create!(
      chat: chat,
      participant: invitee,
      role: :member,
      invitation_accepted: false
    )

    with_current_chat_participant(invitee) do
      patch "/chat/chats/#{chat.id}/decline"
      assert_redirected_to "/chat/chats"
      follow_redirect!
      assert_response :success
    end

    assert_includes response.body, %(data-chat-emit-chat-lifecycle-events="true")
    assert_includes response.body, %(data-chat-lifecycle-event="{&quot;eventName&quot;:&quot;turbo-chat:chat-declined&quot;)
  ensure
    TurboChat.configuration.emit_chat_lifecycle_events = previous_emit_chat_lifecycle_events
  end

  test "decline redirects with migration alert when invitation tracking is unavailable" do
    invitee = User.create!(email: "decline-legacy-invitee@example.com")
    chat = TurboChat::Chat.create!(title: "Decline Legacy Chat")
    invited_membership = TurboChat::ChatMembership.create!(
      chat: chat,
      participant: invitee,
      role: :member,
      invitation_accepted: false
    )

    TurboChat::ChatMembership.stub(:invitation_tracking_supported?, false) do
      with_current_chat_participant(invitee) do
        patch "/chat/chats/#{chat.id}/decline"
        assert_redirected_to "/chat/chats"
      end
    end

    invited_membership.reload
    assert invited_membership.removed_at.nil?
    assert_not invited_membership.invitation_accepted?
  end

  test "chat message create does not allow user-submitted system kind" do
    participant = User.create!(email: "system-kind-guard@example.com")
    chat = TurboChat::Chat.create!(title: "System Kind Guard")
    TurboChat::ChatMembership.create!(chat: chat, participant: participant, role: :member)

    with_current_chat_participant(participant) do
      post "/chat/chats/#{chat.id}/chat_messages", params: {
        chat_message: {
          kind: :system,
          body: "forged system event"
        }
      }
    end

    assert_redirected_to "/chat/chats/#{chat.id}"
    created_message = chat.chat_messages.order(:id).last
    assert_equal "message", created_message.kind
    assert_equal "forged system event", created_message.body
  end

  test "admin can close and reopen chat" do
    admin = User.create!(email: "close-admin@example.com")
    chat = TurboChat::Chat.create!(title: "Close Chat")
    TurboChat::ChatMembership.create!(chat: chat, participant: admin, role: :admin)

    with_current_chat_participant(admin) do
      patch "/chat/chats/#{chat.id}/close"
    end
    assert_redirected_to "/chat/chats/#{chat.id}"
    assert chat.reload.closed?

    with_current_chat_participant(admin) do
      patch "/chat/chats/#{chat.id}/reopen"
    end
    assert_redirected_to "/chat/chats/#{chat.id}"
    assert chat.reload.opened?
  end

  test "closing chat includes lifecycle event payload when enabled" do
    previous_emit_chat_lifecycle_events = TurboChat.configuration.emit_chat_lifecycle_events
    TurboChat.configuration.emit_chat_lifecycle_events = true

    admin = User.create!(email: "close-event-admin@example.com")
    chat = TurboChat::Chat.create!(title: "Close Event Chat")
    TurboChat::ChatMembership.create!(chat: chat, participant: admin, role: :admin)

    with_current_chat_participant(admin) do
      patch "/chat/chats/#{chat.id}/close"
      assert_redirected_to "/chat/chats/#{chat.id}"
      follow_redirect!
      assert_response :success
    end

    assert_includes response.body, %(data-chat-emit-chat-lifecycle-events="true")
    assert_includes response.body, %(data-chat-lifecycle-event="{&quot;eventName&quot;:&quot;turbo-chat:chat-closed&quot;)
  ensure
    TurboChat.configuration.emit_chat_lifecycle_events = previous_emit_chat_lifecycle_events
  end

  test "reopening chat includes lifecycle event payload when enabled" do
    previous_emit_chat_lifecycle_events = TurboChat.configuration.emit_chat_lifecycle_events
    TurboChat.configuration.emit_chat_lifecycle_events = true

    admin = User.create!(email: "reopen-event-admin@example.com")
    chat = TurboChat::Chat.create!(title: "Reopen Event Chat", closed_at: Time.current)
    TurboChat::ChatMembership.create!(chat: chat, participant: admin, role: :admin)

    with_current_chat_participant(admin) do
      patch "/chat/chats/#{chat.id}/reopen"
      assert_redirected_to "/chat/chats/#{chat.id}"
      follow_redirect!
      assert_response :success
    end

    assert_includes response.body, %(data-chat-emit-chat-lifecycle-events="true")
    assert_includes response.body, %(data-chat-lifecycle-event="{&quot;eventName&quot;:&quot;turbo-chat:chat-reopened&quot;)
  ensure
    TurboChat.configuration.emit_chat_lifecycle_events = previous_emit_chat_lifecycle_events
  end

  test "participant can edit own message" do
    participant = User.create!(email: "edit-owner@example.com")
    chat = TurboChat::Chat.create!(title: "Edit Own Message")
    TurboChat::ChatMembership.create!(chat: chat, participant: participant, role: :member)
    message = insert_message!(chat: chat, participant: participant, body: "original")

    with_current_chat_participant(participant) do
      patch "/chat/chats/#{chat.id}/chat_messages/#{message.id}", params: {
        chat_message: { body: "updated body" }
      }
    end

    assert_redirected_to "/chat/chats/#{chat.id}"
    assert_equal "updated body", message.reload.body
  end

  test "participant cannot edit other participant message" do
    viewer = User.create!(email: "edit-viewer@example.com")
    owner = User.create!(email: "edit-owner-other@example.com")
    chat = TurboChat::Chat.create!(title: "Edit Other Message")
    TurboChat::ChatMembership.create!(chat: chat, participant: viewer, role: :member)
    TurboChat::ChatMembership.create!(chat: chat, participant: owner, role: :member)
    message = insert_message!(chat: chat, participant: owner, body: "owner body")

    with_current_chat_participant(viewer) do
      patch "/chat/chats/#{chat.id}/chat_messages/#{message.id}", params: {
        chat_message: { body: "attempted update" }
      }
      assert_redirected_to "/chat/chats/#{chat.id}"
    end

    assert_equal "owner body", message.reload.body
  end

  private

  def with_current_chat_participant(participant)
    original_method = ApplicationController.instance_method(:current_chat_participant)
    ApplicationController.send(:define_method, :current_chat_participant) { participant }
    yield
  ensure
    ApplicationController.send(:define_method, :current_chat_participant, original_method)
  end

  def insert_message!(chat:, participant:, body:)
    TurboChat::ChatMessage.insert_all!(
      [
        {
          chat_id: chat.id,
          participant_type: participant.class.base_class.name,
          participant_id: participant.id,
          kind: TurboChat::ChatMessage.kinds.fetch("message"),
          body: body,
          created_at: Time.current,
          updated_at: Time.current
        }
      ]
    )

    TurboChat::ChatMessage.where(chat: chat, participant: participant).order(id: :desc).first!
  end
end
