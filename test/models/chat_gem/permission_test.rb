require_relative "../../test_helper"

module ChatGem
  class PermissionTest < ActiveSupport::TestCase
    test "role hierarchy controls moderation and chat lifecycle permissions" do
      chat = ChatGem::Chat.create!(title: "Permission Hierarchy")
      admin = User.create!(email: "perm-admin@example.com")
      moderator = User.create!(email: "perm-moderator@example.com")
      member = User.create!(email: "perm-member@example.com")

      admin_membership = ChatGem::ChatMembership.create!(chat: chat, participant: admin, role: :admin)
      moderator_membership = ChatGem::ChatMembership.create!(chat: chat, participant: moderator, role: :moderator)
      member_membership = ChatGem::ChatMembership.create!(chat: chat, participant: member, role: :member)

      moderator_permission = ChatGem::Permission.new(moderator, chat)
      assert moderator_permission.can_mute_member?(member_membership)
      assert moderator_permission.can_timeout_member?(member_membership)
      assert moderator_permission.can_ban_member?(member_membership)
      assert_not moderator_permission.can_mute_member?(moderator_membership)
      assert_not moderator_permission.can_ban_member?(admin_membership)
      assert_not moderator_permission.can_close_chat?
      assert moderator_permission.can_invite_member?

      admin_permission = ChatGem::Permission.new(admin, chat)
      assert admin_permission.can_mute_member?(moderator_membership)
      assert admin_permission.can_ban_member?(moderator_membership)
      assert_not admin_permission.can_ban_member?(admin_membership)
      assert admin_permission.can_close_chat?
      assert admin_permission.can_reopen_chat?
      assert admin_permission.can_invite_member?

      member_permission = ChatGem::Permission.new(member, chat)
      assert_not member_permission.can_mute_member?(moderator_membership)
      assert_not member_permission.can_timeout_member?(moderator_membership)
      assert_not member_permission.can_ban_member?(moderator_membership)
      assert_not member_permission.can_close_chat?
      assert_not member_permission.can_invite_member?
    end

    test "delete message permission follows role hierarchy in the chat" do
      chat = ChatGem::Chat.create!(title: "Delete Permission")
      admin = User.create!(email: "delete-admin@example.com")
      moderator = User.create!(email: "delete-moderator@example.com")
      member = User.create!(email: "delete-member@example.com")

      ChatGem::ChatMembership.create!(chat: chat, participant: admin, role: :admin)
      ChatGem::ChatMembership.create!(chat: chat, participant: moderator, role: :moderator)
      ChatGem::ChatMembership.create!(chat: chat, participant: member, role: :member)

      admin_message = ChatGem::ChatMessage.create!(chat: chat, participant: admin, body: "admin", kind: :message)
      moderator_message = ChatGem::ChatMessage.create!(chat: chat, participant: moderator, body: "mod", kind: :message)
      member_message = ChatGem::ChatMessage.create!(chat: chat, participant: member, body: "member", kind: :message)

      moderator_permission = ChatGem::Permission.new(moderator, chat)
      assert moderator_permission.can_delete_message?(member_message)
      assert_not moderator_permission.can_delete_message?(moderator_message)
      assert_not moderator_permission.can_delete_message?(admin_message)

      admin_permission = ChatGem::Permission.new(admin, chat)
      assert admin_permission.can_delete_message?(moderator_message)
      assert admin_permission.can_delete_message?(member_message)
    end

    test "posting is blocked by mute, timeout, or closed chat while viewing remains allowed for active members" do
      chat = ChatGem::Chat.create!(title: "Posting Guards")
      user = User.create!(email: "posting-guards@example.com")
      membership = ChatGem::ChatMembership.create!(chat: chat, participant: user, role: :member)
      permission = ChatGem::Permission.new(user, chat)

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
      chat = ChatGem::Chat.create!(title: "Removed Membership")
      user = User.create!(email: "removed-membership@example.com")
      membership = ChatGem::ChatMembership.create!(chat: chat, participant: user, removed_at: Time.current)

      permission = ChatGem::Permission.new(user, chat)
      assert_not membership.active?
      assert_not permission.can_view_chat?
      assert_not permission.can_post_message?
    end

    test "custom role permissions are honored" do
      with_custom_role(
        :support_agent,
        name: "Support Agent",
        rank: 1,
        permissions: %i[view_chat post_message delete_message]
      ) do
        chat = ChatGem::Chat.create!(title: "Custom Permission")
        support = User.create!(email: "support-perm@example.com")
        member = User.create!(email: "support-member@example.com")

        ChatGem::ChatMembership.create!(chat: chat, participant: support, role_key: :support_agent)
        member_membership = ChatGem::ChatMembership.create!(chat: chat, participant: member, role: :member)
        member_message = ChatGem::ChatMessage.create!(chat: chat, participant: member, body: "hello", kind: :message)

        permission = ChatGem::Permission.new(support, chat)
        assert permission.can_view_chat?
        assert permission.can_post_message?
        assert permission.can_delete_message?(member_message)
        assert_not permission.can_mute_member?(member_membership)
        assert_not permission.can_close_chat?
      end
    end

    test "mention permissions are role-specific" do
      chat = ChatGem::Chat.create!(title: "Mention Permission")
      admin = User.create!(email: "mention-admin@example.com")
      moderator = User.create!(email: "mention-moderator@example.com")
      member = User.create!(email: "mention-member@example.com")

      ChatGem::ChatMembership.create!(chat: chat, participant: admin, role: :admin)
      ChatGem::ChatMembership.create!(chat: chat, participant: moderator, role: :moderator)
      ChatGem::ChatMembership.create!(chat: chat, participant: member, role: :member)

      admin_permission = ChatGem::Permission.new(admin, chat)
      moderator_permission = ChatGem::Permission.new(moderator, chat)
      member_permission = ChatGem::Permission.new(member, chat)

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
      chat = ChatGem::Chat.create!(title: "Edit Permission")
      owner = User.create!(email: "edit-owner-permission@example.com")
      other = User.create!(email: "edit-other-permission@example.com")

      ChatGem::ChatMembership.create!(chat: chat, participant: owner, role: :member)
      ChatGem::ChatMembership.create!(chat: chat, participant: other, role: :member)

      own_message = ChatGem::ChatMessage.new(chat: chat, participant: owner, kind: :message, body: "own")
      other_message = ChatGem::ChatMessage.new(chat: chat, participant: other, kind: :message, body: "other")

      permission = ChatGem::Permission.new(owner, chat)
      assert permission.can_edit_message?(own_message)
      assert_not permission.can_edit_message?(other_message)

      chat.close!
      assert_not permission.can_edit_message?(own_message)
    end

    private

    def with_custom_role(key, name:, rank:, permissions:)
      config = ChatGem.configuration
      config.add_role(key, name: name, rank: rank, permissions: permissions)
      yield
    ensure
      config.remove_role(key)
    end
  end
end
