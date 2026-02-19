require_relative "../../test_helper"

module TurboChat
  class PermissionTest < ActiveSupport::TestCase
    test "role hierarchy controls moderation and chat lifecycle permissions" do
      chat = TurboChat::Chat.create!(title: "Permission Hierarchy")
      admin = User.create!(email: "perm-admin@example.com")
      moderator = User.create!(email: "perm-moderator@example.com")
      member = User.create!(email: "perm-member@example.com")

      admin_membership = TurboChat::ChatMembership.create!(chat: chat, participant: admin, role: :admin)
      moderator_membership = TurboChat::ChatMembership.create!(chat: chat, participant: moderator, role: :moderator)
      member_membership = TurboChat::ChatMembership.create!(chat: chat, participant: member, role: :member)

      moderator_permission = TurboChat::Permission.new(moderator, chat)
      assert moderator_permission.can_mute_member?(member_membership)
      assert moderator_permission.can_timeout_member?(member_membership)
      assert moderator_permission.can_ban_member?(member_membership)
      assert_not moderator_permission.can_mute_member?(moderator_membership)
      assert_not moderator_permission.can_ban_member?(admin_membership)
      assert_not moderator_permission.can_close_chat?
      assert moderator_permission.can_invite_member?

      admin_permission = TurboChat::Permission.new(admin, chat)
      assert admin_permission.can_mute_member?(moderator_membership)
      assert admin_permission.can_ban_member?(moderator_membership)
      assert_not admin_permission.can_ban_member?(admin_membership)
      assert admin_permission.can_close_chat?
      assert admin_permission.can_reopen_chat?
      assert admin_permission.can_invite_member?

      member_permission = TurboChat::Permission.new(member, chat)
      assert_not member_permission.can_mute_member?(moderator_membership)
      assert_not member_permission.can_timeout_member?(moderator_membership)
      assert_not member_permission.can_ban_member?(moderator_membership)
      assert_not member_permission.can_close_chat?
      assert_not member_permission.can_invite_member?
    end

    test "delete message permission follows role hierarchy in the chat" do
      chat = TurboChat::Chat.create!(title: "Delete Permission")
      admin = User.create!(email: "delete-admin@example.com")
      moderator = User.create!(email: "delete-moderator@example.com")
      member = User.create!(email: "delete-member@example.com")

      TurboChat::ChatMembership.create!(chat: chat, participant: admin, role: :admin)
      TurboChat::ChatMembership.create!(chat: chat, participant: moderator, role: :moderator)
      TurboChat::ChatMembership.create!(chat: chat, participant: member, role: :member)

      admin_message = TurboChat::ChatMessage.create!(chat: chat, participant: admin, body: "admin", kind: :message)
      moderator_message = TurboChat::ChatMessage.create!(chat: chat, participant: moderator, body: "mod", kind: :message)
      member_message = TurboChat::ChatMessage.create!(chat: chat, participant: member, body: "member", kind: :message)

      moderator_permission = TurboChat::Permission.new(moderator, chat)
      assert moderator_permission.can_delete_message?(member_message)
      assert_not moderator_permission.can_delete_message?(moderator_message)
      assert_not moderator_permission.can_delete_message?(admin_message)

      admin_permission = TurboChat::Permission.new(admin, chat)
      assert admin_permission.can_delete_message?(moderator_message)
      assert admin_permission.can_delete_message?(member_message)
    end

    test "delete message permission ignores removed historical memberships" do
      chat = TurboChat::Chat.create!(title: "Delete Permission Historical Membership")
      moderator = User.create!(email: "delete-history-moderator@example.com")
      target = User.create!(email: "delete-history-target@example.com")

      TurboChat::ChatMembership.create!(chat: chat, participant: moderator, role: :moderator)
      TurboChat::ChatMembership.create!(
        chat: chat,
        participant: target,
        role: :member,
        removed_at: 1.day.ago
      )
      TurboChat::ChatMembership.create!(chat: chat, participant: target, role: :admin)

      target_message = TurboChat::ChatMessage.create!(chat: chat, participant: target, body: "admin message", kind: :message)

      moderator_permission = TurboChat::Permission.new(moderator, chat)
      assert_not moderator_permission.can_delete_message?(target_message)
    end

    test "posting is blocked by mute, timeout, or closed chat while viewing remains allowed for active members" do
      chat = TurboChat::Chat.create!(title: "Posting Guards")
      user = User.create!(email: "posting-guards@example.com")
      membership = TurboChat::ChatMembership.create!(chat: chat, participant: user, role: :member)
      permission = TurboChat::Permission.new(user, chat)

      assert permission.can_view_chat?
      assert permission.can_post_message?

      membership.update!(muted: true)
      assert_not permission.can_post_message?

      membership.update!(muted: false, timed_out_until: 2.minutes.from_now)
      assert_not permission.can_post_message?

      membership.update!(timed_out_until: nil)
      chat.close!
      assert permission.can_view_chat?
      assert_not permission.can_post_message?

      chat.reopen!
      assert permission.can_post_message?
    end

    test "removed membership cannot view or post" do
      chat = TurboChat::Chat.create!(title: "Removed Membership")
      user = User.create!(email: "removed-membership@example.com")
      membership = TurboChat::ChatMembership.create!(chat: chat, participant: user, removed_at: Time.current)

      permission = TurboChat::Permission.new(user, chat)
      assert_not membership.active?
      assert_not permission.can_view_chat?
      assert_not permission.can_post_message?
    end

    test "pending invitation cannot view or post until accepted" do
      chat = TurboChat::Chat.create!(title: "Pending Invitation Permission")
      user = User.create!(email: "pending-permission@example.com")
      membership = TurboChat::ChatMembership.create!(
        chat: chat,
        participant: user,
        invitation_accepted: false
      )

      permission = TurboChat::Permission.new(user, chat)
      assert membership.pending?
      assert_not permission.can_view_chat?
      assert_not permission.can_post_message?

      membership.accept_invitation!
      assert permission.can_view_chat?
      assert permission.can_post_message?
    end

    test "custom role permissions are honored" do
      with_custom_role(
        :support_agent,
        name: "Support Agent",
        rank: 1,
        permissions: %i[view_chat post_message delete_message]
      ) do
        chat = TurboChat::Chat.create!(title: "Custom Permission")
        support = User.create!(email: "support-perm@example.com")
        member = User.create!(email: "support-member@example.com")

        TurboChat::ChatMembership.create!(chat: chat, participant: support, role_key: :support_agent)
        member_membership = TurboChat::ChatMembership.create!(chat: chat, participant: member, role: :member)
        member_message = TurboChat::ChatMessage.create!(chat: chat, participant: member, body: "hello", kind: :message)

        permission = TurboChat::Permission.new(support, chat)
        assert permission.can_view_chat?
        assert permission.can_post_message?
        assert permission.can_delete_message?(member_message)
        assert_not permission.can_mute_member?(member_membership)
        assert_not permission.can_close_chat?
      end
    end

    test "mention permissions are role-specific" do
      chat = TurboChat::Chat.create!(title: "Mention Permission")
      admin = User.create!(email: "mention-admin@example.com")
      moderator = User.create!(email: "mention-moderator@example.com")
      member = User.create!(email: "mention-member@example.com")

      TurboChat::ChatMembership.create!(chat: chat, participant: admin, role: :admin)
      TurboChat::ChatMembership.create!(chat: chat, participant: moderator, role: :moderator)
      TurboChat::ChatMembership.create!(chat: chat, participant: member, role: :member)

      admin_permission = TurboChat::Permission.new(admin, chat)
      moderator_permission = TurboChat::Permission.new(moderator, chat)
      member_permission = TurboChat::Permission.new(member, chat)

      assert admin_permission.can_mention_members?
      assert admin_permission.can_mention_all?
      assert admin_permission.can_mention_roles?

      assert moderator_permission.can_mention_members?
      assert moderator_permission.can_mention_all?
      assert moderator_permission.can_mention_roles?

      assert member_permission.can_mention_members?
      assert_not member_permission.can_mention_all?
      assert_not member_permission.can_mention_roles?
    end

    test "message editing is allowed only for own messages while posting is allowed" do
      chat = TurboChat::Chat.create!(title: "Edit Permission")
      owner = User.create!(email: "edit-owner-permission@example.com")
      other = User.create!(email: "edit-other-permission@example.com")

      TurboChat::ChatMembership.create!(chat: chat, participant: owner, role: :member)
      TurboChat::ChatMembership.create!(chat: chat, participant: other, role: :member)

      own_message = TurboChat::ChatMessage.new(chat: chat, participant: owner, kind: :message, body: "own")
      other_message = TurboChat::ChatMessage.new(chat: chat, participant: other, kind: :message, body: "other")

      permission = TurboChat::Permission.new(owner, chat)
      assert permission.can_edit_message?(own_message)
      assert_not permission.can_edit_message?(other_message)

      chat.close!
      assert_not permission.can_edit_message?(own_message)
    end

    private

    def with_custom_role(key, name:, rank:, permissions:)
      config = TurboChat.configuration
      config.add_role(key, name: name, rank: rank, permissions: permissions)
      yield
    ensure
      config.remove_role(key)
    end
  end
end
