require_relative "../../test_helper"

module ChatGem
  class ModerationTest < ActiveSupport::TestCase
    test "moderator can mute timeout and ban a member" do
      context = build_chat_with_roles("moderation-flow")
      moderator = context[:moderator]
      member_membership = context[:member_membership]

      ChatGem::Moderation.mute_member!(actor: moderator, membership: member_membership)
      assert member_membership.reload.muted?

      timeout_until = 15.minutes.from_now.change(usec: 0)
      ChatGem::Moderation.timeout_member!(actor: moderator, membership: member_membership, until_time: timeout_until)
      assert_equal timeout_until.to_i, member_membership.reload.timed_out_until.to_i

      ChatGem::Moderation.clear_timeout!(actor: moderator, membership: member_membership)
      assert_nil member_membership.reload.timed_out_until

      ChatGem::Moderation.ban_member!(actor: moderator, membership: member_membership)
      member_membership.reload
      assert member_membership.removed_at.present?
      assert_not member_membership.muted?
      assert_nil member_membership.timed_out_until
    end

    test "moderator cannot ban admin" do
      context = build_chat_with_roles("moderation-admin")

      error = assert_raises(ChatGem::Moderation::AuthorizationError) do
        ChatGem::Moderation.ban_member!(
          actor: context[:moderator],
          membership: context[:admin_membership]
        )
      end

      assert_includes error.message, "Not allowed"
    end

    test "member cannot mute another member" do
      context = build_chat_with_roles("moderation-member")

      assert_raises(ChatGem::Moderation::AuthorizationError) do
        ChatGem::Moderation.mute_member!(
          actor: context[:member],
          membership: context[:moderator_membership]
        )
      end
    end

    test "admin can close and reopen a chat" do
      context = build_chat_with_roles("moderation-close")
      chat = context[:chat]
      admin = context[:admin]

      ChatGem::Moderation.close_chat!(actor: admin, chat: chat)
      assert chat.reload.closed?

      ChatGem::Moderation.reopen_chat!(actor: admin, chat: chat)
      assert chat.reload.opened?
    end

    test "message deletion follows permissions" do
      context = build_chat_with_roles("moderation-delete")
      chat = context[:chat]

      member_message = ChatGem::ChatMessage.create!(
        chat: chat,
        participant: context[:member],
        body: "delete me",
        kind: :message
      )
      admin_message = ChatGem::ChatMessage.create!(
        chat: chat,
        participant: context[:admin],
        body: "keep me",
        kind: :message
      )

      assert ChatGem::Moderation.delete_message!(actor: context[:moderator], message: member_message)
      assert_not ChatGem::ChatMessage.exists?(member_message.id)

      assert_raises(ChatGem::Moderation::AuthorizationError) do
        ChatGem::Moderation.delete_message!(actor: context[:moderator], message: admin_message)
      end
      assert ChatGem::ChatMessage.exists?(admin_message.id)
    end

    test "emits moderation notifications when enabled" do
      context = build_chat_with_roles("moderation-events")
      moderator = context[:moderator]
      member_membership = context[:member_membership]

      original_emit_moderation_events = ChatGem.configuration.emit_moderation_events
      ChatGem.configuration.emit_moderation_events = true

      event_names = []
      callback = lambda do |*args|
        event = ActiveSupport::Notifications::Event.new(*args)
        event_names << event.name
      end

      ActiveSupport::Notifications.subscribed(callback, /chat_gem\.moderation\./) do
        ChatGem::Moderation.mute_member!(actor: moderator, membership: member_membership)
        ChatGem::Moderation.timeout_member!(actor: moderator, membership: member_membership, until_time: 10.minutes.from_now)
        ChatGem::Moderation.clear_timeout!(actor: moderator, membership: member_membership)
        ChatGem::Moderation.ban_member!(actor: moderator, membership: member_membership)
      end

      assert_includes event_names, "chat_gem.moderation.member_muted"
      assert_includes event_names, "chat_gem.moderation.member_timed_out"
      assert_includes event_names, "chat_gem.moderation.member_timeout_cleared"
      assert_includes event_names, "chat_gem.moderation.member_banned"
    ensure
      ChatGem.configuration.emit_moderation_events = original_emit_moderation_events
    end

    test "does not emit moderation notifications when disabled" do
      context = build_chat_with_roles("moderation-events-off")
      moderator = context[:moderator]
      member_membership = context[:member_membership]

      original_emit_moderation_events = ChatGem.configuration.emit_moderation_events
      ChatGem.configuration.emit_moderation_events = false

      event_names = []
      callback = lambda do |*args|
        event = ActiveSupport::Notifications::Event.new(*args)
        event_names << event.name
      end

      ActiveSupport::Notifications.subscribed(callback, /chat_gem\.moderation\./) do
        ChatGem::Moderation.mute_member!(actor: moderator, membership: member_membership)
      end

      assert_empty event_names
    ensure
      ChatGem.configuration.emit_moderation_events = original_emit_moderation_events
    end

    private

    def build_chat_with_roles(prefix)
      chat = ChatGem::Chat.create!(title: "#{prefix}-chat")
      admin = User.create!(email: "#{prefix}-admin@example.com")
      moderator = User.create!(email: "#{prefix}-moderator@example.com")
      member = User.create!(email: "#{prefix}-member@example.com")

      {
        chat: chat,
        admin: admin,
        moderator: moderator,
        member: member,
        admin_membership: ChatGem::ChatMembership.create!(chat: chat, participant: admin, role: :admin),
        moderator_membership: ChatGem::ChatMembership.create!(chat: chat, participant: moderator, role: :moderator),
        member_membership: ChatGem::ChatMembership.create!(chat: chat, participant: member, role: :member)
      }
    end
  end
end
