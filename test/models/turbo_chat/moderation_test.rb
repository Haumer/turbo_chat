require_relative "../../test_helper"

module TurboChat
  class ModerationTest < ActiveSupport::TestCase
    test "moderator can mute timeout and ban a member" do
      context = build_chat_with_roles("moderation-flow")
      chat = context[:chat]
      moderator = context[:moderator]
      member_membership = context[:member_membership]

      TurboChat::Moderation.mute_member!(actor: moderator, membership: member_membership)
      assert member_membership.reload.muted?

      timeout_until = 15.minutes.from_now.change(usec: 0)
      TurboChat::Moderation.timeout_member!(actor: moderator, membership: member_membership, until_time: timeout_until)
      assert_equal timeout_until.to_i, member_membership.reload.timed_out_until.to_i

      TurboChat::Moderation.clear_timeout!(actor: moderator, membership: member_membership)
      assert_nil member_membership.reload.timed_out_until

      TurboChat::Moderation.ban_member!(actor: moderator, membership: member_membership)
      member_membership.reload
      assert member_membership.removed_at.present?
      assert_not member_membership.muted?
      assert_nil member_membership.timed_out_until

      system_message_bodies = chat.chat_messages.system.order(:id).pluck(:body)
      assert_includes system_message_bodies, "#{moderator.email} muted #{context[:member].email}."
      assert_includes system_message_bodies, "#{moderator.email} timed out #{context[:member].email}."
      assert_includes system_message_bodies, "#{moderator.email} cleared timeout for #{context[:member].email}."
      assert_includes system_message_bodies, "#{moderator.email} removed #{context[:member].email} from the chat."
    end

    test "moderator cannot ban admin" do
      context = build_chat_with_roles("moderation-admin")

      error = assert_raises(TurboChat::Moderation::AuthorizationError) do
        TurboChat::Moderation.ban_member!(
          actor: context[:moderator],
          membership: context[:admin_membership]
        )
      end

      assert_includes error.message, "Not allowed"
    end

    test "member cannot mute another member" do
      context = build_chat_with_roles("moderation-member")

      assert_raises(TurboChat::Moderation::AuthorizationError) do
        TurboChat::Moderation.mute_member!(
          actor: context[:member],
          membership: context[:moderator_membership]
        )
      end
    end

    test "admin can close and reopen a chat" do
      context = build_chat_with_roles("moderation-close")
      chat = context[:chat]
      admin = context[:admin]

      TurboChat::Moderation.close_chat!(actor: admin, chat: chat)
      assert chat.reload.closed?

      TurboChat::Moderation.reopen_chat!(actor: admin, chat: chat)
      assert chat.reload.opened?
    end

    test "message deletion follows permissions" do
      context = build_chat_with_roles("moderation-delete")
      chat = context[:chat]

      member_message = TurboChat::ChatMessage.create!(
        chat: chat,
        participant: context[:member],
        body: "delete me",
        kind: :message
      )
      admin_message = TurboChat::ChatMessage.create!(
        chat: chat,
        participant: context[:admin],
        body: "keep me",
        kind: :message
      )

      assert TurboChat::Moderation.delete_message!(actor: context[:moderator], message: member_message)
      assert_not TurboChat::ChatMessage.exists?(member_message.id)

      assert_raises(TurboChat::Moderation::AuthorizationError) do
        TurboChat::Moderation.delete_message!(actor: context[:moderator], message: admin_message)
      end
      assert TurboChat::ChatMessage.exists?(admin_message.id)
    end

    test "emits moderation notifications when enabled" do
      context = build_chat_with_roles("moderation-events")
      moderator = context[:moderator]
      member_membership = context[:member_membership]

      original_emit_moderation_events = TurboChat.configuration.emit_moderation_events
      TurboChat.configuration.emit_moderation_events = true

      event_names = []
      callback = lambda do |*args|
        event = ActiveSupport::Notifications::Event.new(*args)
        event_names << event.name
      end

      ActiveSupport::Notifications.subscribed(callback, /turbo_chat\.moderation\./) do
        TurboChat::Moderation.mute_member!(actor: moderator, membership: member_membership)
        TurboChat::Moderation.timeout_member!(actor: moderator, membership: member_membership, until_time: 10.minutes.from_now)
        TurboChat::Moderation.clear_timeout!(actor: moderator, membership: member_membership)
        TurboChat::Moderation.ban_member!(actor: moderator, membership: member_membership)
      end

      assert_includes event_names, "turbo_chat.moderation.member_muted"
      assert_includes event_names, "turbo_chat.moderation.member_timed_out"
      assert_includes event_names, "turbo_chat.moderation.member_timeout_cleared"
      assert_includes event_names, "turbo_chat.moderation.member_banned"
    ensure
      TurboChat.configuration.emit_moderation_events = original_emit_moderation_events
    end

    test "does not emit moderation notifications when disabled" do
      context = build_chat_with_roles("moderation-events-off")
      moderator = context[:moderator]
      member_membership = context[:member_membership]

      original_emit_moderation_events = TurboChat.configuration.emit_moderation_events
      TurboChat.configuration.emit_moderation_events = false

      event_names = []
      callback = lambda do |*args|
        event = ActiveSupport::Notifications::Event.new(*args)
        event_names << event.name
      end

      ActiveSupport::Notifications.subscribed(callback, /turbo_chat\.moderation\./) do
        TurboChat::Moderation.mute_member!(actor: moderator, membership: member_membership)
      end

      assert_empty event_names
    ensure
      TurboChat.configuration.emit_moderation_events = original_emit_moderation_events
    end

    private

    def build_chat_with_roles(prefix)
      chat = TurboChat::Chat.create!(title: "#{prefix}-chat")
      admin = User.create!(email: "#{prefix}-admin@example.com")
      moderator = User.create!(email: "#{prefix}-moderator@example.com")
      member = User.create!(email: "#{prefix}-member@example.com")

      {
        chat: chat,
        admin: admin,
        moderator: moderator,
        member: member,
        admin_membership: TurboChat::ChatMembership.create!(chat: chat, participant: admin, role: :admin),
        moderator_membership: TurboChat::ChatMembership.create!(chat: chat, participant: moderator, role: :moderator),
        member_membership: TurboChat::ChatMembership.create!(chat: chat, participant: member, role: :member)
      }
    end
  end
end
