require_relative "../test_helper"

class ChatManagementTest < ActionDispatch::IntegrationTest
  teardown do
    ChatGem::ChatMessage.delete_all
    ChatGem::ChatMembership.delete_all
    ChatGem::Chat.delete_all
    User.delete_all
  end

  test "admin can invite participant to chat" do
    admin = User.create!(email: "invite-admin@example.com")
    invitee = User.create!(email: "invite-target@example.com")
    chat = ChatGem::Chat.create!(title: "Invite Chat")
    ChatGem::ChatMembership.create!(chat: chat, participant: admin, role: :admin)

    with_chat_current_participant(admin) do
      post "/chat/chats/#{chat.id}/chat_memberships", params: {
        chat_membership: {
          participant_type: "User",
          participant_id: invitee.id
        }
      }
    end

    assert_redirected_to "/chat/chats/#{chat.id}"
    invited_membership = ChatGem::ChatMembership.find_by!(chat: chat, participant: invitee)
    assert invited_membership.pending?
    assert_not invited_membership.active?
  end

  test "inviting participant includes lifecycle event payload when enabled" do
    previous_emit_chat_lifecycle_events = ChatGem.configuration.emit_chat_lifecycle_events
    ChatGem.configuration.emit_chat_lifecycle_events = true

    admin = User.create!(email: "invite-event-admin@example.com")
    invitee = User.create!(email: "invite-event-target@example.com")
    chat = ChatGem::Chat.create!(title: "Invite Event Chat")
    ChatGem::ChatMembership.create!(chat: chat, participant: admin, role: :admin)

    with_chat_current_participant(admin) do
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
    assert_includes response.body, %(data-chat-lifecycle-event="{&quot;eventName&quot;:&quot;chat-gem:chat-invited&quot;)
  ensure
    ChatGem.configuration.emit_chat_lifecycle_events = previous_emit_chat_lifecycle_events
  end

  test "member cannot invite participant to chat" do
    member = User.create!(email: "invite-member@example.com")
    invitee = User.create!(email: "invite-blocked@example.com")
    chat = ChatGem::Chat.create!(title: "Invite Forbidden")
    ChatGem::ChatMembership.create!(chat: chat, participant: member, role: :member)

    with_chat_current_participant(member) do
      post "/chat/chats/#{chat.id}/chat_memberships", params: {
        chat_membership: {
          participant_type: "User",
          participant_id: invitee.id
        }
      }
    end

    assert_response :forbidden
    assert_not ChatGem::ChatMembership.active.exists?(chat: chat, participant: invitee)
  end

  test "admin cannot invite participant with mismatched participant type" do
    admin = User.create!(email: "invite-admin-type-check@example.com")
    chat = ChatGem::Chat.create!(title: "Invite Type Check")
    ChatGem::ChatMembership.create!(chat: chat, participant: admin, role: :admin)

    klass_name = "ChatGemInviteExternalUser"
    Object.send(:remove_const, klass_name) if Object.const_defined?(klass_name)

    external_participant_class = Class.new(ApplicationRecord) do
      self.table_name = "users"
      acts_as_chat_participant
    end
    Object.const_set(klass_name, external_participant_class)
    external_participant = external_participant_class.create!(email: "invite-external@example.com")

    with_chat_current_participant(admin) do
      post "/chat/chats/#{chat.id}/chat_memberships", params: {
        chat_membership: {
          participant_type: klass_name,
          participant_id: external_participant.id
        }
      }
    end

    assert_redirected_to "/chat/chats/#{chat.id}"
    assert_not ChatGem::ChatMembership.active.exists?(
      chat: chat,
      participant_type: klass_name,
      participant_id: external_participant.id
    )
  ensure
    Object.send(:remove_const, klass_name) if defined?(klass_name) && Object.const_defined?(klass_name)
  end

  test "participant can leave chat" do
    participant = User.create!(email: "leave-user@example.com")
    chat = ChatGem::Chat.create!(title: "Leave Chat")
    membership = ChatGem::ChatMembership.create!(chat: chat, participant: participant, role: :member)

    with_chat_current_participant(participant) do
      patch "/chat/chats/#{chat.id}/leave"
    end

    assert_redirected_to "/chat/chats"
    assert membership.reload.removed_at.present?
  end

  test "leaving chat includes lifecycle event payload when enabled" do
    previous_emit_chat_lifecycle_events = ChatGem.configuration.emit_chat_lifecycle_events
    ChatGem.configuration.emit_chat_lifecycle_events = true

    participant = User.create!(email: "leave-event-user@example.com")
    chat = ChatGem::Chat.create!(title: "Leave Event Chat")
    ChatGem::ChatMembership.create!(chat: chat, participant: participant, role: :member)

    with_chat_current_participant(participant) do
      patch "/chat/chats/#{chat.id}/leave"
      assert_redirected_to "/chat/chats"
      follow_redirect!
      assert_response :success
    end

    assert_includes response.body, %(data-chat-emit-chat-lifecycle-events="true")
    assert_includes response.body, %(data-chat-lifecycle-event="{&quot;eventName&quot;:&quot;chat-gem:chat-left&quot;)
  ensure
    ChatGem.configuration.emit_chat_lifecycle_events = previous_emit_chat_lifecycle_events
  end

  test "invited participant can accept invitation from chats index" do
    admin = User.create!(email: "accept-admin@example.com")
    invitee = User.create!(email: "accept-invitee@example.com")
    chat = ChatGem::Chat.create!(title: "Accept Invite Chat")
    ChatGem::ChatMembership.create!(chat: chat, participant: admin, role: :admin)
    invited_membership = ChatGem::ChatMembership.create!(
      chat: chat,
      participant: invitee,
      role: :member,
      invitation_accepted: false
    )

    with_chat_current_participant(invitee) do
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
  end

  test "accepting invitation includes frontend event payload when enabled" do
    previous_emit_invitation_events = ChatGem.configuration.emit_invitation_events
    ChatGem.configuration.emit_invitation_events = true

    invitee = User.create!(email: "accept-event-invitee@example.com")
    chat = ChatGem::Chat.create!(title: "Accept Event Chat")
    ChatGem::ChatMembership.create!(
      chat: chat,
      participant: invitee,
      role: :member,
      invitation_accepted: false
    )

    with_chat_current_participant(invitee) do
      patch "/chat/chats/#{chat.id}/accept"
      assert_redirected_to "/chat/chats"
      follow_redirect!
      assert_response :success
    end

    assert_includes response.body, %(data-chat-emit-invitation-events="true")
    assert_includes response.body, %(data-chat-invitation-accepted="{&quot;chatId&quot;:&quot;#{chat.id}&quot;)
  ensure
    ChatGem.configuration.emit_invitation_events = previous_emit_invitation_events
  end

  test "accepting invitation includes lifecycle event payload when enabled" do
    previous_emit_chat_lifecycle_events = ChatGem.configuration.emit_chat_lifecycle_events
    ChatGem.configuration.emit_chat_lifecycle_events = true

    invitee = User.create!(email: "accept-lifecycle-invitee@example.com")
    chat = ChatGem::Chat.create!(title: "Accept Lifecycle Chat")
    ChatGem::ChatMembership.create!(
      chat: chat,
      participant: invitee,
      role: :member,
      invitation_accepted: false
    )

    with_chat_current_participant(invitee) do
      patch "/chat/chats/#{chat.id}/accept"
      assert_redirected_to "/chat/chats"
      follow_redirect!
      assert_response :success
    end

    assert_includes response.body, %(data-chat-emit-chat-lifecycle-events="true")
    assert_includes response.body, %(data-chat-lifecycle-event="{&quot;eventName&quot;:&quot;chat-gem:chat-joined&quot;)
  ensure
    ChatGem.configuration.emit_chat_lifecycle_events = previous_emit_chat_lifecycle_events
  end

  test "accept redirects with migration alert when invitation tracking is unavailable" do
    invitee = User.create!(email: "accept-legacy-invitee@example.com")
    chat = ChatGem::Chat.create!(title: "Accept Legacy Chat")
    invited_membership = ChatGem::ChatMembership.create!(
      chat: chat,
      participant: invitee,
      role: :member,
      invitation_accepted: false
    )

    ChatGem::ChatMembership.stub(:invitation_tracking_supported?, false) do
      with_chat_current_participant(invitee) do
        patch "/chat/chats/#{chat.id}/accept"
        assert_redirected_to "/chat/chats"
      end
    end

    assert_not invited_membership.reload.invitation_accepted?
  end

  test "invited participant can decline invitation from chats index" do
    invitee = User.create!(email: "decline-invitee@example.com")
    chat = ChatGem::Chat.create!(title: "Decline Invite Chat")
    invited_membership = ChatGem::ChatMembership.create!(
      chat: chat,
      participant: invitee,
      role: :member,
      invitation_accepted: false
    )

    with_chat_current_participant(invitee) do
      patch "/chat/chats/#{chat.id}/decline"
      assert_redirected_to "/chat/chats"
    end

    invited_membership.reload
    assert invited_membership.removed_at.present?
    assert_not invited_membership.active?
  end

  test "declining invitation includes lifecycle event payload when enabled" do
    previous_emit_chat_lifecycle_events = ChatGem.configuration.emit_chat_lifecycle_events
    ChatGem.configuration.emit_chat_lifecycle_events = true

    invitee = User.create!(email: "decline-event-invitee@example.com")
    chat = ChatGem::Chat.create!(title: "Decline Event Chat")
    ChatGem::ChatMembership.create!(
      chat: chat,
      participant: invitee,
      role: :member,
      invitation_accepted: false
    )

    with_chat_current_participant(invitee) do
      patch "/chat/chats/#{chat.id}/decline"
      assert_redirected_to "/chat/chats"
      follow_redirect!
      assert_response :success
    end

    assert_includes response.body, %(data-chat-emit-chat-lifecycle-events="true")
    assert_includes response.body, %(data-chat-lifecycle-event="{&quot;eventName&quot;:&quot;chat-gem:chat-declined&quot;)
  ensure
    ChatGem.configuration.emit_chat_lifecycle_events = previous_emit_chat_lifecycle_events
  end

  test "decline redirects with migration alert when invitation tracking is unavailable" do
    invitee = User.create!(email: "decline-legacy-invitee@example.com")
    chat = ChatGem::Chat.create!(title: "Decline Legacy Chat")
    invited_membership = ChatGem::ChatMembership.create!(
      chat: chat,
      participant: invitee,
      role: :member,
      invitation_accepted: false
    )

    ChatGem::ChatMembership.stub(:invitation_tracking_supported?, false) do
      with_chat_current_participant(invitee) do
        patch "/chat/chats/#{chat.id}/decline"
        assert_redirected_to "/chat/chats"
      end
    end

    invited_membership.reload
    assert invited_membership.removed_at.nil?
    assert_not invited_membership.invitation_accepted?
  end

  test "admin can close and reopen chat" do
    admin = User.create!(email: "close-admin@example.com")
    chat = ChatGem::Chat.create!(title: "Close Chat")
    ChatGem::ChatMembership.create!(chat: chat, participant: admin, role: :admin)

    with_chat_current_participant(admin) do
      patch "/chat/chats/#{chat.id}/close"
    end
    assert_redirected_to "/chat/chats/#{chat.id}"
    assert chat.reload.closed?

    with_chat_current_participant(admin) do
      patch "/chat/chats/#{chat.id}/reopen"
    end
    assert_redirected_to "/chat/chats/#{chat.id}"
    assert chat.reload.opened?
  end

  test "closing chat includes lifecycle event payload when enabled" do
    previous_emit_chat_lifecycle_events = ChatGem.configuration.emit_chat_lifecycle_events
    ChatGem.configuration.emit_chat_lifecycle_events = true

    admin = User.create!(email: "close-event-admin@example.com")
    chat = ChatGem::Chat.create!(title: "Close Event Chat")
    ChatGem::ChatMembership.create!(chat: chat, participant: admin, role: :admin)

    with_chat_current_participant(admin) do
      patch "/chat/chats/#{chat.id}/close"
      assert_redirected_to "/chat/chats/#{chat.id}"
      follow_redirect!
      assert_response :success
    end

    assert_includes response.body, %(data-chat-emit-chat-lifecycle-events="true")
    assert_includes response.body, %(data-chat-lifecycle-event="{&quot;eventName&quot;:&quot;chat-gem:chat-closed&quot;)
  ensure
    ChatGem.configuration.emit_chat_lifecycle_events = previous_emit_chat_lifecycle_events
  end

  test "reopening chat includes lifecycle event payload when enabled" do
    previous_emit_chat_lifecycle_events = ChatGem.configuration.emit_chat_lifecycle_events
    ChatGem.configuration.emit_chat_lifecycle_events = true

    admin = User.create!(email: "reopen-event-admin@example.com")
    chat = ChatGem::Chat.create!(title: "Reopen Event Chat", closed_at: Time.current)
    ChatGem::ChatMembership.create!(chat: chat, participant: admin, role: :admin)

    with_chat_current_participant(admin) do
      patch "/chat/chats/#{chat.id}/reopen"
      assert_redirected_to "/chat/chats/#{chat.id}"
      follow_redirect!
      assert_response :success
    end

    assert_includes response.body, %(data-chat-emit-chat-lifecycle-events="true")
    assert_includes response.body, %(data-chat-lifecycle-event="{&quot;eventName&quot;:&quot;chat-gem:chat-reopened&quot;)
  ensure
    ChatGem.configuration.emit_chat_lifecycle_events = previous_emit_chat_lifecycle_events
  end

  test "participant can edit own message" do
    participant = User.create!(email: "edit-owner@example.com")
    chat = ChatGem::Chat.create!(title: "Edit Own Message")
    ChatGem::ChatMembership.create!(chat: chat, participant: participant, role: :member)
    message = insert_message!(chat: chat, participant: participant, body: "original")

    with_chat_current_participant(participant) do
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
    chat = ChatGem::Chat.create!(title: "Edit Other Message")
    ChatGem::ChatMembership.create!(chat: chat, participant: viewer, role: :member)
    ChatGem::ChatMembership.create!(chat: chat, participant: owner, role: :member)
    message = insert_message!(chat: chat, participant: owner, body: "owner body")

    with_chat_current_participant(viewer) do
      patch "/chat/chats/#{chat.id}/chat_messages/#{message.id}", params: {
        chat_message: { body: "attempted update" }
      }
      assert_redirected_to "/chat/chats/#{chat.id}"
    end

    assert_equal "owner body", message.reload.body
  end

  private

  def with_chat_current_participant(participant)
    original_method = ApplicationController.instance_method(:chat_current_participant)
    ApplicationController.send(:define_method, :chat_current_participant) { participant }
    yield
  ensure
    ApplicationController.send(:define_method, :chat_current_participant, original_method)
  end

  def insert_message!(chat:, participant:, body:)
    ChatGem::ChatMessage.insert_all!(
      [
        {
          chat_id: chat.id,
          participant_type: participant.class.base_class.name,
          participant_id: participant.id,
          kind: ChatGem::ChatMessage.kinds.fetch("message"),
          body: body,
          created_at: Time.current,
          updated_at: Time.current
        }
      ]
    )

    ChatGem::ChatMessage.where(chat: chat, participant: participant).order(id: :desc).first!
  end
end
