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

    test "participant_display_name prefers username when present" do
      participant = User.new(email: "alex@example.com")
      participant.define_singleton_method(:username) { "agent_alex" }
      message = ChatGem::ChatMessage.new(participant: participant)

      assert_equal "agent_alex", message.participant_display_name
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

    test "member role cannot mention @all or role tokens" do
      member = User.create!(email: "member-mention-check@example.com")
      chat = ChatGem::Chat.create!(title: "Mention Guard")
      ChatGem::ChatMembership.create!(chat: chat, participant: member, role: :member)

      all_message = ChatGem::ChatMessage.new(chat: chat, participant: member, body: "ping @all", kind: :message)
      role_message = ChatGem::ChatMessage.new(chat: chat, participant: member, body: "ping @ADMIN", kind: :message)

      assert_not all_message.valid?
      assert_includes all_message.errors[:body], "cannot mention @all"
      assert_not role_message.valid?
      assert_includes role_message.errors[:body], "cannot mention roles"
    end

    test "moderator role can mention members @all and role tokens" do
      moderator = User.create!(email: "moderator-mention-check@example.com")
      chat = ChatGem::Chat.create!(title: "Mention Allow")
      ChatGem::ChatMembership.create!(chat: chat, participant: moderator, role: :moderator)

      message = ChatGem::ChatMessage.new(
        chat: chat,
        participant: moderator,
        body: "hey @member @all @ADMIN",
        kind: :message
      )

      assert message.valid?
    end

    test "mention validation is skipped when mentions are disabled" do
      member = User.create!(email: "member-mention-disabled@example.com")
      chat = ChatGem::Chat.create!(title: "Mention Disabled")
      ChatGem::ChatMembership.create!(chat: chat, participant: member, role: :member)

      with_chat_configuration(enable_mentions: false) do
        message = ChatGem::ChatMessage.new(
          chat: chat,
          participant: member,
          body: "hey @all and @ADMIN",
          kind: :message
        )

        assert message.valid?
      end
    end

    test "mention validation fails closed when permission adapter errors" do
      member = User.create!(email: "member-mention-adapter-error@example.com")
      chat = ChatGem::Chat.create!(title: "Mention Adapter Error")
      ChatGem::ChatMembership.create!(chat: chat, participant: member, role: :member)

      broken_adapter = Class.new do
        def initialize(*)
          raise ArgumentError, "broken adapter"
        end
      end

      with_chat_configuration(permission_adapter: broken_adapter) do
        message = ChatGem::ChatMessage.new(
          chat: chat,
          participant: member,
          body: "hey @all",
          kind: :message
        )

        assert_not message.valid?
        assert_includes message.errors[:body], "mentions cannot be validated at this time"
      end
    end

    test "blocked words reject message when moderation action is reject" do
      member = User.create!(email: "member-blocked-reject@example.com")
      chat = ChatGem::Chat.create!(title: "Blocked Reject")
      ChatGem::ChatMembership.create!(chat: chat, participant: member, role: :member)

      with_chat_configuration(blocked_words: ["badword"], blocked_words_action: :reject) do
        message = ChatGem::ChatMessage.new(
          chat: chat,
          participant: member,
          body: "this has badword inside",
          kind: :message
        )

        assert_not message.valid?
        assert_includes message.errors[:body], "contains blocked language"
      end
    end

    test "blocked words scramble message when moderation action is scramble" do
      member = User.create!(email: "member-blocked-scramble@example.com")
      chat = ChatGem::Chat.create!(title: "Blocked Scramble")
      ChatGem::ChatMembership.create!(chat: chat, participant: member, role: :member)

      with_chat_configuration(
        blocked_words: ["badword"],
        blocked_words_action: :scramble
      ) do
        message = ChatGem::ChatMessage.create!(
          chat: chat,
          participant: member,
          body: "this has badword inside",
          kind: :message
        )

        scrambled_word = message.body.match(/\Athis has ([^\s]+) inside\z/)&.captures&.first

        assert_not_nil scrambled_word
        assert_not_equal "badword", scrambled_word.downcase
        assert_equal "badword".chars.sort, scrambled_word.downcase.chars.sort
      end
    end

    test "blocked words do not reject when list is empty" do
      member = User.create!(email: "member-blocked-empty@example.com")
      chat = ChatGem::Chat.create!(title: "Blocked Empty")
      ChatGem::ChatMembership.create!(chat: chat, participant: member, role: :member)

      with_chat_configuration(blocked_words: [], blocked_words_action: :reject) do
        message = ChatGem::ChatMessage.new(
          chat: chat,
          participant: member,
          body: "this has badword inside",
          kind: :message
        )

        assert message.valid?
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

    test "formats updated timestamp with default formatter" do
      user = User.create!(email: "updated-time@example.com")
      chat = ChatGem::Chat.create!(title: "Updated Time")
      ChatGem::ChatMembership.create!(chat: chat, participant: user)
      message = ChatGem::ChatMessage.create!(chat: chat, participant: user, body: "clock", kind: :message)
      timestamp = Time.zone.local(2026, 2, 1, 14, 30, 0)
      message.update_column(:updated_at, timestamp)
      message.reload

      with_chat_configuration do
        assert_equal I18n.l(timestamp.in_time_zone, format: :long), message.formatted_updated_timestamp
      end
    end

    test "supports custom timestamp formatter for updated timestamp" do
      user = User.create!(email: "custom-updated-time@example.com")
      chat = ChatGem::Chat.create!(title: "Custom Updated Time")
      ChatGem::ChatMembership.create!(chat: chat, participant: user)
      message = ChatGem::ChatMessage.create!(chat: chat, participant: user, body: "clock", kind: :message)

      with_chat_configuration(
        timestamp_formatter: ->(timestamp, chat_message) { "TS-#{chat_message.id}-#{timestamp.to_i}" }
      ) do
        assert_equal "TS-#{message.id}-#{message.updated_at.to_i}", message.formatted_updated_timestamp
      end
    end

    test "edited? tracks whether updated timestamp is newer than created timestamp" do
      user = User.create!(email: "edited-flag@example.com")
      chat = ChatGem::Chat.create!(title: "Edited Flag")
      ChatGem::ChatMembership.create!(chat: chat, participant: user)
      message = ChatGem::ChatMessage.create!(chat: chat, participant: user, body: "original", kind: :message)

      message.update_column(:updated_at, message.created_at)
      message.reload
      assert_not message.edited?

      message.update!(body: "updated")
      assert message.reload.edited?
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
        enable_mentions: config.enable_mentions,
        permission_adapter: config.permission_adapter,
        blocked_words: config.blocked_words,
        blocked_words_action: config.blocked_words_action,
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
