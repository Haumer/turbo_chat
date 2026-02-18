require_relative "../../test_helper"

module ChatGem
  class ChatTest < ActiveSupport::TestCase
    test "active? uses the default window and ignores signals" do
      user = User.create!(email: "active-window@example.com")

      recent_chat = ChatGem::Chat.create!(title: "Recent")
      ChatGem::ChatMessage.create!(
        chat: recent_chat,
        participant: user,
        body: "recent",
        kind: :message,
        created_at: 4.minutes.ago
      )

      old_chat = ChatGem::Chat.create!(title: "Old")
      ChatGem::ChatMessage.create!(
        chat: old_chat,
        participant: user,
        body: "old",
        kind: :message,
        created_at: 6.minutes.ago
      )

      signal_only_chat = ChatGem::Chat.create!(title: "Signal Only")
      ChatGem::ChatMessage.create!(
        chat: signal_only_chat,
        participant: user,
        kind: :signal,
        signal_type: :typing,
        created_at: Time.current
      )

      assert recent_chat.active?
      assert_not old_chat.active?
      assert_not signal_only_chat.active?
    end

    test "active? supports configurable window" do
      user = User.create!(email: "configurable-window@example.com")
      chat = ChatGem::Chat.create!(title: "Configurable")
      ChatGem::ChatMessage.create!(
        chat: chat,
        participant: user,
        body: "within ten minutes",
        kind: :message,
        created_at: 6.minutes.ago
      )

      with_active_chat_window(10.minutes) do
        assert chat.active?
      end
    end

    test "active and inactive scopes follow configured window" do
      user = User.create!(email: "scope-window@example.com")

      active_chat = ChatGem::Chat.create!(title: "Active")
      ChatGem::ChatMessage.create!(
        chat: active_chat,
        participant: user,
        body: "recent message",
        kind: :message,
        created_at: 2.minutes.ago
      )

      inactive_chat = ChatGem::Chat.create!(title: "Inactive")
      ChatGem::ChatMessage.create!(
        chat: inactive_chat,
        participant: user,
        body: "stale message",
        kind: :message,
        created_at: 8.minutes.ago
      )

      no_message_chat = ChatGem::Chat.create!(title: "No Message")

      with_active_chat_window(5.minutes) do
        assert_equal [active_chat.id], ChatGem::Chat.active.order(:id).pluck(:id)
        assert_equal [inactive_chat.id, no_message_chat.id].sort, ChatGem::Chat.inactive.order(:id).pluck(:id).sort
      end
    end

    test "activity_window_seconds requires a positive value" do
      error = assert_raises(ArgumentError) do
        ChatGem::Chat.activity_window_seconds(0)
      end

      assert_includes error.message, "active chat window"
    end

    test "visible_messages returns only latest messages in ascending order when limited" do
      user = User.create!(email: "visible-messages-limit@example.com")
      chat = ChatGem::Chat.create!(title: "Visible Messages")

      oldest = ChatGem::ChatMessage.create!(
        chat: chat,
        participant: user,
        body: "oldest",
        kind: :message,
        created_at: 3.minutes.ago
      )
      middle = ChatGem::ChatMessage.create!(
        chat: chat,
        participant: user,
        body: "middle",
        kind: :message,
        created_at: 2.minutes.ago
      )
      newest = ChatGem::ChatMessage.create!(
        chat: chat,
        participant: user,
        body: "newest",
        kind: :message,
        created_at: 1.minute.ago
      )

      assert_equal [middle.id, newest.id], chat.visible_messages(limit: 2).pluck(:id)
      assert_equal [oldest.id, middle.id, newest.id], chat.visible_messages(limit: nil).pluck(:id)
    end

    test "chat can be closed and reopened with scopes" do
      open_chat = ChatGem::Chat.create!(title: "Open Chat")
      closed_chat = ChatGem::Chat.create!(title: "Closed Chat")

      closed_chat.close!
      assert closed_chat.reload.closed?
      assert closed_chat.closed_at.present?
      assert open_chat.reload.opened?

      assert_equal [closed_chat.id], ChatGem::Chat.closed.order(:id).pluck(:id)
      assert_equal [open_chat.id], ChatGem::Chat.opened.order(:id).pluck(:id)

      closed_chat.reopen!
      assert closed_chat.reload.opened?
      assert_nil closed_chat.closed_at
    end

    private

    def with_active_chat_window(window)
      previous_window = ChatGem.configuration.active_chat_window
      ChatGem.configuration.active_chat_window = window
      yield
    ensure
      ChatGem.configuration.active_chat_window = previous_window
    end
  end
end
