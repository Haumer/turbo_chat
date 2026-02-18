require_relative "../../test_helper"

module ChatGem
  class ChatMessageTest < ActiveSupport::TestCase
    test "orders by created_at and id" do
      user = User.create!(email: "order@example.com")
      chat = ChatGem::Chat.create!(title: "Ordering")
      ChatGem::ChatMembership.create!(chat: chat, participant: user)

      first = ChatGem::ChatMessage.create!(chat: chat, participant: user, body: "one", kind: :message, created_at: 1.minute.ago)
      second = ChatGem::ChatMessage.create!(chat: chat, participant: user, body: "two", kind: :message, created_at: 1.minute.ago)
      third = ChatGem::ChatMessage.create!(chat: chat, participant: user, body: "three", kind: :message, created_at: Time.current)

      assert_equal [first.id, second.id, third.id], chat.chat_messages.ordered.pluck(:id)
    end

    test "requires signal_type for signal" do
      user = User.create!(email: "signal@example.com")
      chat = ChatGem::Chat.create!(title: "Signals")
      ChatGem::ChatMembership.create!(chat: chat, participant: user)

      message = ChatGem::ChatMessage.new(chat: chat, participant: user, kind: :signal)

      assert_not message.valid?
      assert_includes message.errors[:signal_type], "can't be blank"
    end

    test "messages_only excludes signal rows" do
      user = User.create!(email: "kindfilter@example.com")
      chat = ChatGem::Chat.create!(title: "Kinds")
      ChatGem::ChatMembership.create!(chat: chat, participant: user)

      visible = ChatGem::ChatMessage.create!(chat: chat, participant: user, body: "visible", kind: :message)
      ChatGem::ChatMessage.create!(chat: chat, participant: user, kind: :signal, signal_type: :typing)

      assert_equal [visible.id], chat.chat_messages.messages_only.ordered.pluck(:id)
    end

    test "validates default max message length" do
      user = User.create!(email: "max-length-default@example.com")
      chat = ChatGem::Chat.create!(title: "Max Length Default")
      ChatGem::ChatMembership.create!(chat: chat, participant: user)

      message = ChatGem::ChatMessage.new(
        chat: chat,
        participant: user,
        kind: :message,
        body: "a" * 1001
      )

      assert_not message.valid?
      assert_includes message.errors[:body], "is too long (maximum is 1000 characters)"
    end

    test "supports configurable max message length" do
      user = User.create!(email: "max-length-custom@example.com")
      chat = ChatGem::Chat.create!(title: "Max Length Custom")
      ChatGem::ChatMembership.create!(chat: chat, participant: user)

      with_chat_configuration(max_message_length: 5) do
        short_message = ChatGem::ChatMessage.new(
          chat: chat,
          participant: user,
          kind: :message,
          body: "hello"
        )
        long_message = ChatGem::ChatMessage.new(
          chat: chat,
          participant: user,
          kind: :message,
          body: "toolong"
        )

        assert short_message.valid?
        assert_not long_message.valid?
        assert_includes long_message.errors[:body], "is too long (maximum is 5 characters)"
      end
    end

    test "replace_signal keeps only latest participant signal" do
      user = User.create!(email: "replace_signal@example.com")
      chat = ChatGem::Chat.create!(title: "Replace Signal")
      ChatGem::ChatMembership.create!(chat: chat, participant: user)

      ChatGem::ChatMessage.start_signal!(chat: chat, participant: user, signal_type: :typing)
      replaced = ChatGem::ChatMessage.replace_signal!(chat: chat, participant: user, signal_type: :planning)

      signals = chat.chat_messages.signal.where(participant: user).ordered
      assert_equal [replaced.id], signals.pluck(:id)
      assert_equal "planning", replaced.signal_type
    end

    test "with_signal clears participant signal after block" do
      user = User.create!(email: "with_signal@example.com")
      chat = ChatGem::Chat.create!(title: "With Signal")
      ChatGem::ChatMembership.create!(chat: chat, participant: user)

      result = ChatGem::ChatMessage.with_signal(chat: chat, participant: user, signal_type: :thinking) do
        current = chat.chat_messages.signal.where(participant: user).ordered.last
        assert current.present?
        assert_equal "thinking", current.signal_type
        :ok
      end

      assert_equal :ok, result
      assert_equal 0, chat.chat_messages.signal.where(participant: user).count
    end

    test "message submit does not replace participant signal rows by default" do
      user = User.create!(email: "submit-default@example.com")
      chat = ChatGem::Chat.create!(title: "Submit Default")
      ChatGem::ChatMembership.create!(chat: chat, participant: user)

      ChatGem::ChatMessage.start_signal!(chat: chat, participant: user, signal_type: :typing)
      ChatGem::ChatMessage.create!(chat: chat, participant: user, body: "sent", kind: :message)

      assert_equal 1, chat.chat_messages.signal.where(participant: user).count
    end

    test "message submit replaces only submitter signal rows when enabled" do
      sender = User.create!(email: "submit-enabled@example.com")
      other = User.create!(email: "submit-enabled-other@example.com")
      chat = ChatGem::Chat.create!(title: "Submit Enabled")
      ChatGem::ChatMembership.create!(chat: chat, participant: sender)
      ChatGem::ChatMembership.create!(chat: chat, participant: other)

      ChatGem::ChatMessage.start_signal!(chat: chat, participant: sender, signal_type: :typing)
      ChatGem::ChatMessage.start_signal!(chat: chat, participant: other, signal_type: :thinking)

      with_chat_configuration(replace_signals_on_message_submit: true) do
        ChatGem::ChatMessage.create!(chat: chat, participant: sender, body: "sent", kind: :message)
      end

      assert_equal 0, chat.chat_messages.signal.where(participant: sender).count
      assert_equal 1, chat.chat_messages.signal.where(participant: other).count
    end

    test "clear_signals broadcasts signal refresh" do
      user = User.create!(email: "clear_broadcast@example.com")
      chat = ChatGem::Chat.create!(title: "Clear Broadcast")
      ChatGem::ChatMembership.create!(chat: chat, participant: user)
      ChatGem::ChatMessage.start_signal!(chat: chat, participant: user, signal_type: :typing)

      called = false
      Turbo::StreamsChannel.stub(:broadcast_update_to, lambda { |_stream, **_opts| called = true }) do
        ChatGem::ChatMessage.clear_signals!(chat: chat, participant: user)
      end

      assert called
    end

    test "formats timestamp with default formatter" do
      user = User.create!(email: "time@example.com")
      chat = ChatGem::Chat.create!(title: "Time")
      ChatGem::ChatMembership.create!(chat: chat, participant: user)
      message = ChatGem::ChatMessage.create!(chat: chat, participant: user, body: "clock", kind: :message)
      timestamp = Time.zone.local(2026, 2, 1, 13, 45, 0)
      message.update_column(:created_at, timestamp)
      message.reload

      with_chat_configuration do
        assert_equal I18n.l(timestamp.in_time_zone, format: :long), message.formatted_timestamp
      end
    end

    test "supports custom timestamp formatter" do
      user = User.create!(email: "customtime@example.com")
      chat = ChatGem::Chat.create!(title: "Custom Time")
      ChatGem::ChatMembership.create!(chat: chat, participant: user)
      message = ChatGem::ChatMessage.create!(chat: chat, participant: user, body: "clock", kind: :message)

      with_chat_configuration(
        timestamp_formatter: ->(timestamp, chat_message) { "TS-#{chat_message.id}-#{timestamp.to_i}" }
      ) do
        assert_equal "TS-#{message.id}-#{message.created_at.to_i}", message.formatted_timestamp
      end
    end

    test "formats participant membership role and supports role formatter" do
      user = User.create!(email: "roleshow@example.com")
      chat = ChatGem::Chat.create!(title: "Role Labels")
      ChatGem::ChatMembership.create!(chat: chat, participant: user, role: :moderator)
      message = ChatGem::ChatMessage.create!(chat: chat, participant: user, body: "role", kind: :message)

      with_chat_configuration do
        assert_equal "Moderator", message.formatted_participant_role
      end

      with_chat_configuration(
        role_formatter: ->(role, chat_message) { "#{role.upcase}-#{chat_message.id}" }
      ) do
        assert_equal "MODERATOR-#{message.id}", message.formatted_participant_role
      end
    end

    test "formats configured custom role name when formatter is blank" do
      user = User.create!(email: "custom-role-label@example.com")
      chat = ChatGem::Chat.create!(title: "Custom Role Labels")
      config = ChatGem.configuration

      config.add_role(
        :support_agent,
        name: "Support Agent",
        rank: 1,
        permissions: %i[view_chat post_message]
      )

      ChatGem::ChatMembership.create!(chat: chat, participant: user, role_key: :support_agent)
      message = ChatGem::ChatMessage.create!(chat: chat, participant: user, body: "role", kind: :message)

      with_chat_configuration(role_formatter: ->(_role, _chat_message) { nil }) do
        assert_equal "Support Agent", message.formatted_participant_role
      end
    ensure
      config.remove_role(:support_agent) if config
    end

    private

    def with_chat_configuration(overrides = {})
      config = ChatGem.configuration
      original = {
        show_timestamp: config.show_timestamp,
        show_role: config.show_role,
        max_message_length: config.max_message_length,
        replace_signals_on_message_submit: config.replace_signals_on_message_submit,
        timestamp_formatter: config.timestamp_formatter,
        role_formatter: config.role_formatter
      }

      overrides.each do |key, value|
        config.public_send("#{key}=", value)
      end

      yield
    ensure
      original.each do |key, value|
        config.public_send("#{key}=", value)
      end
    end
  end
end
