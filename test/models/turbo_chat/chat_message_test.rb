require_relative "../../test_helper"

module TurboChat
  class ChatMessageTest < ActiveSupport::TestCase
    test "orders by created_at and id" do
      user = User.create!(email: "order@example.com")
      chat = TurboChat::Chat.create!(title: "Ordering")
      TurboChat::ChatMembership.create!(chat: chat, participant: user)

      first = TurboChat::ChatMessage.create!(chat: chat, participant: user, body: "one", kind: :message, created_at: 1.minute.ago)
      second = TurboChat::ChatMessage.create!(chat: chat, participant: user, body: "two", kind: :message, created_at: 1.minute.ago)
      third = TurboChat::ChatMessage.create!(chat: chat, participant: user, body: "three", kind: :message, created_at: Time.current)

      assert_equal [first.id, second.id, third.id], chat.chat_messages.ordered.pluck(:id)
    end

    test "requires signal_type for signal" do
      user = User.create!(email: "signal@example.com")
      chat = TurboChat::Chat.create!(title: "Signals")
      TurboChat::ChatMembership.create!(chat: chat, participant: user)

      message = TurboChat::ChatMessage.new(chat: chat, participant: user, kind: :signal)

      assert_not message.valid?
      assert_includes message.errors[:signal_type], "can't be blank"
    end

    test "defaults source to app and normalizes external_id" do
      user = User.create!(email: "source-default@example.com")
      chat = TurboChat::Chat.create!(title: "Source Default")
      TurboChat::ChatMembership.create!(chat: chat, participant: user)

      message = TurboChat::ChatMessage.create!(
        chat: chat,
        participant: user,
        body: "hello",
        kind: :message,
        source: "  ",
        external_id: "  provider-123  "
      )

      assert_equal "app", message.source
      assert_equal "provider-123", message.external_id
    end

    test "source must use a normalized key format" do
      user = User.create!(email: "source-format@example.com")
      chat = TurboChat::Chat.create!(title: "Source Format")
      TurboChat::ChatMembership.create!(chat: chat, participant: user)

      message = TurboChat::ChatMessage.new(
        chat: chat,
        participant: user,
        body: "hello",
        kind: :message,
        source: "whatsapp+api"
      )

      assert_not message.valid?
      assert_includes message.errors[:source], "is invalid"
    end

    test "external_id uniqueness is scoped by chat and source" do
      user = User.create!(email: "source-uniq@example.com")
      other_chat = TurboChat::Chat.create!(title: "Source Other Chat")
      chat = TurboChat::Chat.create!(title: "Source Uniqueness")
      TurboChat::ChatMembership.create!(chat: chat, participant: user)
      TurboChat::ChatMembership.create!(chat: other_chat, participant: user)

      TurboChat::ChatMessage.create!(
        chat: chat,
        participant: user,
        body: "first",
        kind: :message,
        source: "whatsapp",
        external_id: "abc-1"
      )

      duplicate = TurboChat::ChatMessage.new(
        chat: chat,
        participant: user,
        body: "duplicate",
        kind: :message,
        source: "whatsapp",
        external_id: "abc-1"
      )

      same_external_other_source = TurboChat::ChatMessage.new(
        chat: chat,
        participant: user,
        body: "other source",
        kind: :message,
        source: "sms_gateway",
        external_id: "abc-1"
      )

      same_external_other_chat = TurboChat::ChatMessage.new(
        chat: other_chat,
        participant: user,
        body: "other chat",
        kind: :message,
        source: "whatsapp",
        external_id: "abc-1"
      )

      assert_not duplicate.valid?
      assert_includes duplicate.errors[:external_id], "has already been taken"
      assert same_external_other_source.valid?
      assert same_external_other_chat.valid?
    end

    test "requires signal_text for custom signals" do
      user = User.create!(email: "custom-signal@example.com")
      chat = TurboChat::Chat.create!(title: "Custom Signals")
      TurboChat::ChatMembership.create!(chat: chat, participant: user)

      message = TurboChat::ChatMessage.new(
        chat: chat,
        participant: user,
        kind: :signal,
        signal_type: :custom,
        body: "   "
      )

      assert_not message.valid?
      assert_includes message.errors[:signal_text], "can't be blank"
    end

    test "messages_only excludes signal and system rows" do
      user = User.create!(email: "kindfilter@example.com")
      chat = TurboChat::Chat.create!(title: "Kinds")
      TurboChat::ChatMembership.create!(chat: chat, participant: user)

      visible = TurboChat::ChatMessage.create!(chat: chat, participant: user, body: "visible", kind: :message)
      TurboChat::ChatMessage.create!(chat: chat, participant: user, kind: :signal, signal_type: :typing)
      TurboChat::ChatMessage.create!(chat: chat, participant: user, body: "system", kind: :system)

      assert_equal [visible.id], chat.chat_messages.messages_only.ordered.pluck(:id)
    end

    test "timeline includes message and system rows but excludes signals" do
      user = User.create!(email: "timeline-kindfilter@example.com")
      chat = TurboChat::Chat.create!(title: "Timeline Kinds")
      TurboChat::ChatMembership.create!(chat: chat, participant: user)

      message = TurboChat::ChatMessage.create!(chat: chat, participant: user, body: "visible", kind: :message)
      system = TurboChat::ChatMessage.create!(chat: chat, participant: user, body: "joined", kind: :system)
      TurboChat::ChatMessage.create!(chat: chat, participant: user, kind: :signal, signal_type: :typing)

      assert_equal [message.id, system.id], chat.chat_messages.timeline.ordered.pluck(:id)
    end

    test "membership system message helper creates invite event copy" do
      inviter = User.create!(email: "invite-copy-inviter@example.com")
      invitee = User.create!(email: "invite-copy-invitee@example.com")
      chat = TurboChat::Chat.create!(title: "System Invite Copy")

      message = TurboChat::ChatMessage.create_membership_system_message!(
        chat: chat,
        actor: inviter,
        event: :invited,
        subject: invitee
      )

      assert message.present?
      assert message.system?
      assert_equal "#{inviter.email} invited #{invitee.email}.", message.body
    end

    test "membership system message helper creates leave event copy" do
      participant = User.create!(email: "leave-copy-user@example.com")
      chat = TurboChat::Chat.create!(title: "System Leave Copy")

      message = TurboChat::ChatMessage.create_membership_system_message!(
        chat: chat,
        actor: participant,
        event: :left
      )

      assert message.present?
      assert message.system?
      assert_equal "#{participant.email} left the chat.", message.body
    end

    test "membership system message helper creates moderation event copy" do
      moderator = User.create!(email: "moderation-copy-moderator@example.com")
      member = User.create!(email: "moderation-copy-member@example.com")
      chat = TurboChat::Chat.create!(title: "System Moderation Copy")

      message = TurboChat::ChatMessage.create_membership_system_message!(
        chat: chat,
        actor: moderator,
        event: :muted,
        subject: member
      )

      assert message.present?
      assert message.system?
      assert_equal "#{moderator.email} muted #{member.email}.", message.body
    end

    test "membership system messages can be disabled via configuration" do
      inviter = User.create!(email: "system-copy-off-inviter@example.com")
      invitee = User.create!(email: "system-copy-off-invitee@example.com")
      chat = TurboChat::Chat.create!(title: "System Copy Disabled")

      with_chat_configuration(system_messages: false) do
        message = TurboChat::ChatMessage.create_membership_system_message!(
          chat: chat,
          actor: inviter,
          event: :invited,
          subject: invitee
        )

        assert_nil message
      end
    end

    test "participant_display_name prefers username when present" do
      participant = User.new(email: "alex@example.com")
      participant.define_singleton_method(:username) { "agent_alex" }
      message = TurboChat::ChatMessage.new(participant: participant)

      assert_equal "agent_alex", message.participant_display_name
    end

    test "validates default max message length" do
      user = User.create!(email: "max-length-default@example.com")
      chat = TurboChat::Chat.create!(title: "Max Length Default")
      TurboChat::ChatMembership.create!(chat: chat, participant: user)

      message = TurboChat::ChatMessage.new(
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
      chat = TurboChat::Chat.create!(title: "Max Length Custom")
      TurboChat::ChatMembership.create!(chat: chat, participant: user)

      with_chat_configuration(max_message_length: 5) do
        short_message = TurboChat::ChatMessage.new(
          chat: chat,
          participant: user,
          kind: :message,
          body: "hello"
        )
        long_message = TurboChat::ChatMessage.new(
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
      chat = TurboChat::Chat.create!(title: "Mention Guard")
      TurboChat::ChatMembership.create!(chat: chat, participant: member, role: :member)

      all_message = TurboChat::ChatMessage.new(chat: chat, participant: member, body: "ping @all", kind: :message)
      role_message = TurboChat::ChatMessage.new(chat: chat, participant: member, body: "ping @ADMIN", kind: :message)

      assert_not all_message.valid?
      assert_includes all_message.errors[:body], "cannot mention @all"
      assert_not role_message.valid?
      assert_includes role_message.errors[:body], "cannot mention roles"
    end

    test "moderator role can mention members @all and role tokens" do
      moderator = User.create!(email: "moderator-mention-check@example.com")
      chat = TurboChat::Chat.create!(title: "Mention Allow")
      TurboChat::ChatMembership.create!(chat: chat, participant: moderator, role: :moderator)

      message = TurboChat::ChatMessage.new(
        chat: chat,
        participant: moderator,
        body: "hey @member @all @ADMIN",
        kind: :message
      )

      assert message.valid?
    end

    test "mention validation is skipped when mentions are disabled" do
      member = User.create!(email: "member-mention-disabled@example.com")
      chat = TurboChat::Chat.create!(title: "Mention Disabled")
      TurboChat::ChatMembership.create!(chat: chat, participant: member, role: :member)

      with_chat_configuration(enable_mentions: false) do
        message = TurboChat::ChatMessage.new(
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
      chat = TurboChat::Chat.create!(title: "Mention Adapter Error")
      TurboChat::ChatMembership.create!(chat: chat, participant: member, role: :member)

      broken_adapter = Class.new do
        def initialize(*)
          raise ArgumentError, "broken adapter"
        end
      end

      with_chat_configuration(permission_adapter: broken_adapter) do
        message = TurboChat::ChatMessage.new(
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
      chat = TurboChat::Chat.create!(title: "Blocked Reject")
      TurboChat::ChatMembership.create!(chat: chat, participant: member, role: :member)

      with_chat_configuration(blocked_words: ["badword"], blocked_words_action: :reject) do
        message = TurboChat::ChatMessage.new(
          chat: chat,
          participant: member,
          body: "this has badword inside",
          kind: :message
        )

        assert_not message.valid?
        assert_includes message.errors[:body], "contains blocked language"
      end
    end

    test "blocked words emit detect and reject notifications when enabled" do
      member = User.create!(email: "member-blocked-notify-reject@example.com")
      chat = TurboChat::Chat.create!(title: "Blocked Notify Reject")
      TurboChat::ChatMembership.create!(chat: chat, participant: member, role: :member)

      events = []
      callback = lambda do |*args|
        event = ActiveSupport::Notifications::Event.new(*args)
        events << event
      end

      with_chat_configuration(
        blocked_words: ["badword"],
        blocked_words_action: :reject,
        emit_blocked_words_events: true
      ) do
        ActiveSupport::Notifications.subscribed(callback, /turbo_chat\.blocked_words\./) do
          message = TurboChat::ChatMessage.new(
            chat: chat,
            participant: member,
            body: "this has badword inside",
            kind: :message
          )

          assert_not message.valid?
        end
      end

      event_names = events.map(&:name)
      assert_includes event_names, "turbo_chat.blocked_words.detected"
      assert_includes event_names, "turbo_chat.blocked_words.rejected"
    end

    test "blocked words scramble message when moderation action is scramble" do
      member = User.create!(email: "member-blocked-scramble@example.com")
      chat = TurboChat::Chat.create!(title: "Blocked Scramble")
      TurboChat::ChatMembership.create!(chat: chat, participant: member, role: :member)

      with_chat_configuration(
        blocked_words: ["badword"],
        blocked_words_action: :scramble
      ) do
        message = TurboChat::ChatMessage.create!(
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

    test "blocked words emit detect and scramble notifications when enabled" do
      member = User.create!(email: "member-blocked-notify-scramble@example.com")
      chat = TurboChat::Chat.create!(title: "Blocked Notify Scramble")
      TurboChat::ChatMembership.create!(chat: chat, participant: member, role: :member)

      events = []
      callback = lambda do |*args|
        event = ActiveSupport::Notifications::Event.new(*args)
        events << event
      end

      with_chat_configuration(
        blocked_words: ["badword"],
        blocked_words_action: :scramble,
        emit_blocked_words_events: true
      ) do
        ActiveSupport::Notifications.subscribed(callback, /turbo_chat\.blocked_words\./) do
          TurboChat::ChatMessage.create!(
            chat: chat,
            participant: member,
            body: "this has badword inside",
            kind: :message
          )
        end
      end

      event_names = events.map(&:name)
      assert_includes event_names, "turbo_chat.blocked_words.detected"
      assert_includes event_names, "turbo_chat.blocked_words.scrambled"
    end

    test "blocked words notifications are disabled by default" do
      member = User.create!(email: "member-blocked-notify-off@example.com")
      chat = TurboChat::Chat.create!(title: "Blocked Notify Off")
      TurboChat::ChatMembership.create!(chat: chat, participant: member, role: :member)

      events = []
      callback = lambda do |*args|
        event = ActiveSupport::Notifications::Event.new(*args)
        events << event
      end

      with_chat_configuration(
        blocked_words: ["badword"],
        blocked_words_action: :reject,
        emit_blocked_words_events: false
      ) do
        ActiveSupport::Notifications.subscribed(callback, /turbo_chat\.blocked_words\./) do
          message = TurboChat::ChatMessage.new(
            chat: chat,
            participant: member,
            body: "this has badword inside",
            kind: :message
          )

          assert_not message.valid?
        end
      end

      assert_empty events
    end

    test "blocked words do not reject when list is empty" do
      member = User.create!(email: "member-blocked-empty@example.com")
      chat = TurboChat::Chat.create!(title: "Blocked Empty")
      TurboChat::ChatMembership.create!(chat: chat, participant: member, role: :member)

      with_chat_configuration(blocked_words: [], blocked_words_action: :reject) do
        message = TurboChat::ChatMessage.new(
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
      chat = TurboChat::Chat.create!(title: "Replace Signal")
      TurboChat::ChatMembership.create!(chat: chat, participant: user)

      TurboChat::ChatMessage.start_signal!(chat: chat, participant: user, signal_type: :typing)
      replaced = TurboChat::ChatMessage.replace_signal!(chat: chat, participant: user, signal_type: :planning)

      signals = chat.chat_messages.signal.where(participant: user).ordered
      assert_equal [replaced.id], signals.pluck(:id)
      assert_equal "planning", replaced.signal_type
    end

    test "replace_signal supports custom signal text" do
      user = User.create!(email: "replace-custom-signal@example.com")
      chat = TurboChat::Chat.create!(title: "Replace Custom Signal")
      TurboChat::ChatMembership.create!(chat: chat, participant: user)

      replaced = TurboChat::ChatMessage.replace_signal!(
        chat: chat,
        participant: user,
        signal_type: :custom,
        signal_text: "Hello"
      )

      assert_equal "custom", replaced.signal_type
      assert_equal "Hello", replaced.signal_text
      assert_equal "Hello", replaced.body
    end

    test "replace_signal broadcasts a single signal refresh" do
      user = User.create!(email: "replace_signal_broadcast@example.com")
      chat = TurboChat::Chat.create!(title: "Replace Signal Broadcast")
      TurboChat::ChatMembership.create!(chat: chat, participant: user)

      TurboChat::ChatMessage.start_signal!(chat: chat, participant: user, signal_type: :typing)

      broadcast_count = 0
      Turbo::StreamsChannel.stub(:broadcast_update_to, lambda { |_stream, **_opts| broadcast_count += 1 }) do
        TurboChat::ChatMessage.replace_signal!(chat: chat, participant: user, signal_type: :planning)
      end

      assert_equal 1, broadcast_count
    end

    test "append_start_position? normalizes configured insert position values" do
      user = User.create!(email: "insert-position-check@example.com")
      chat = TurboChat::Chat.create!(title: "Insert Position Check")
      TurboChat::ChatMembership.create!(chat: chat, participant: user)

      with_chat_configuration(message_insert_position: "append_start") do
        message = TurboChat::ChatMessage.new(chat: chat, participant: user, kind: :message, body: "hello")
        assert_equal true, message.send(:append_start_position?)
      end

      with_chat_configuration(message_insert_position: "start") do
        message = TurboChat::ChatMessage.new(chat: chat, participant: user, kind: :message, body: "hello")
        assert_equal true, message.send(:append_start_position?)
      end

      with_chat_configuration(message_insert_position: "append_end") do
        message = TurboChat::ChatMessage.new(chat: chat, participant: user, kind: :message, body: "hello")
        assert_equal false, message.send(:append_start_position?)
      end

      with_chat_configuration(message_insert_position: "bogus") do
        message = TurboChat::ChatMessage.new(chat: chat, participant: user, kind: :message, body: "hello")
        assert_equal false, message.send(:append_start_position?)
      end
    end

    test "start_signal ignores signal_text for non-custom signal types" do
      user = User.create!(email: "non-custom-signal-text@example.com")
      chat = TurboChat::Chat.create!(title: "Non Custom Signal Text")
      TurboChat::ChatMembership.create!(chat: chat, participant: user)

      signal = TurboChat::ChatMessage.start_signal!(
        chat: chat,
        participant: user,
        signal_type: :typing,
        signal_text: "Should be ignored"
      )

      assert_equal "typing", signal.signal_type
      assert_nil signal.signal_text
      assert_equal "", signal.body
    end

    test "with_signal clears participant signal after block" do
      user = User.create!(email: "with_signal@example.com")
      chat = TurboChat::Chat.create!(title: "With Signal")
      TurboChat::ChatMembership.create!(chat: chat, participant: user)

      result = TurboChat::ChatMessage.with_signal(chat: chat, participant: user, signal_type: :thinking) do
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
      chat = TurboChat::Chat.create!(title: "Submit Default")
      TurboChat::ChatMembership.create!(chat: chat, participant: user)

      TurboChat::ChatMessage.start_signal!(chat: chat, participant: user, signal_type: :typing)
      TurboChat::ChatMessage.create!(chat: chat, participant: user, body: "sent", kind: :message)

      assert_equal 1, chat.chat_messages.signal.where(participant: user).count
    end

    test "message submit replaces only submitter signal rows when enabled" do
      sender = User.create!(email: "submit-enabled@example.com")
      other = User.create!(email: "submit-enabled-other@example.com")
      chat = TurboChat::Chat.create!(title: "Submit Enabled")
      TurboChat::ChatMembership.create!(chat: chat, participant: sender)
      TurboChat::ChatMembership.create!(chat: chat, participant: other)

      TurboChat::ChatMessage.start_signal!(chat: chat, participant: sender, signal_type: :typing)
      TurboChat::ChatMessage.start_signal!(chat: chat, participant: other, signal_type: :thinking)

      with_chat_configuration(replace_signals_on_message_submit: true) do
        TurboChat::ChatMessage.create!(chat: chat, participant: sender, body: "sent", kind: :message)
      end

      assert_equal 0, chat.chat_messages.signal.where(participant: sender).count
      assert_equal 1, chat.chat_messages.signal.where(participant: other).count
    end

    test "clear_signals broadcasts signal refresh" do
      user = User.create!(email: "clear_broadcast@example.com")
      chat = TurboChat::Chat.create!(title: "Clear Broadcast")
      TurboChat::ChatMembership.create!(chat: chat, participant: user)
      TurboChat::ChatMessage.start_signal!(chat: chat, participant: user, signal_type: :typing)

      called = false
      Turbo::StreamsChannel.stub(:broadcast_update_to, lambda { |_stream, **_opts| called = true }) do
        TurboChat::ChatMessage.clear_signals!(chat: chat, participant: user)
      end

      assert called
    end

    test "formats timestamp with default formatter" do
      user = User.create!(email: "time@example.com")
      chat = TurboChat::Chat.create!(title: "Time")
      TurboChat::ChatMembership.create!(chat: chat, participant: user)
      message = TurboChat::ChatMessage.create!(chat: chat, participant: user, body: "clock", kind: :message)
      timestamp = Time.zone.local(2026, 2, 1, 13, 45, 0)
      message.update_column(:created_at, timestamp)
      message.reload

      with_chat_configuration do
        assert_equal I18n.l(timestamp.in_time_zone, format: :long), message.formatted_timestamp
      end
    end

    test "supports custom timestamp formatter" do
      user = User.create!(email: "customtime@example.com")
      chat = TurboChat::Chat.create!(title: "Custom Time")
      TurboChat::ChatMembership.create!(chat: chat, participant: user)
      message = TurboChat::ChatMessage.create!(chat: chat, participant: user, body: "clock", kind: :message)

      with_chat_configuration(
        timestamp_formatter: ->(timestamp, chat_message) { "TS-#{chat_message.id}-#{timestamp.to_i}" }
      ) do
        assert_equal "TS-#{message.id}-#{message.created_at.to_i}", message.formatted_timestamp
      end
    end

    test "formats updated timestamp with default formatter" do
      user = User.create!(email: "updated-time@example.com")
      chat = TurboChat::Chat.create!(title: "Updated Time")
      TurboChat::ChatMembership.create!(chat: chat, participant: user)
      message = TurboChat::ChatMessage.create!(chat: chat, participant: user, body: "clock", kind: :message)
      timestamp = Time.zone.local(2026, 2, 1, 14, 30, 0)
      message.update_column(:updated_at, timestamp)
      message.reload

      with_chat_configuration do
        assert_equal I18n.l(timestamp.in_time_zone, format: :long), message.formatted_updated_timestamp
      end
    end

    test "supports custom timestamp formatter for updated timestamp" do
      user = User.create!(email: "custom-updated-time@example.com")
      chat = TurboChat::Chat.create!(title: "Custom Updated Time")
      TurboChat::ChatMembership.create!(chat: chat, participant: user)
      message = TurboChat::ChatMessage.create!(chat: chat, participant: user, body: "clock", kind: :message)

      with_chat_configuration(
        timestamp_formatter: ->(timestamp, chat_message) { "TS-#{chat_message.id}-#{timestamp.to_i}" }
      ) do
        assert_equal "TS-#{message.id}-#{message.updated_at.to_i}", message.formatted_updated_timestamp
      end
    end

    test "edited? tracks whether updated timestamp is newer than created timestamp" do
      user = User.create!(email: "edited-flag@example.com")
      chat = TurboChat::Chat.create!(title: "Edited Flag")
      TurboChat::ChatMembership.create!(chat: chat, participant: user)
      message = TurboChat::ChatMessage.create!(chat: chat, participant: user, body: "original", kind: :message)

      message.update_column(:updated_at, message.created_at)
      message.reload
      assert_not message.edited?

      message.update!(body: "updated")
      assert message.reload.edited?
    end

    test "formats participant membership role and supports role formatter" do
      user = User.create!(email: "roleshow@example.com")
      chat = TurboChat::Chat.create!(title: "Role Labels")
      TurboChat::ChatMembership.create!(chat: chat, participant: user, role: :moderator)
      message = TurboChat::ChatMessage.create!(chat: chat, participant: user, body: "role", kind: :message)

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
      chat = TurboChat::Chat.create!(title: "Custom Role Labels")
      config = TurboChat.configuration

      config.add_role(
        :support_agent,
        name: "Support Agent",
        rank: 1,
        permissions: %i[view_chat post_message]
      )

      TurboChat::ChatMembership.create!(chat: chat, participant: user, role_key: :support_agent)
      message = TurboChat::ChatMessage.create!(chat: chat, participant: user, body: "role", kind: :message)

      with_chat_configuration(role_formatter: ->(_role, _chat_message) { nil }) do
        assert_equal "Support Agent", message.formatted_participant_role
      end
    ensure
      config.remove_role(:support_agent) if config
    end

    private

    def with_chat_configuration(overrides = {})
      config = TurboChat.configuration
      original = {
        show_timestamp: config.show_timestamp,
        show_role: config.show_role,
        max_message_length: config.max_message_length,
        enable_mentions: config.enable_mentions,
        permission_adapter: config.permission_adapter,
        blocked_words: config.blocked_words,
        blocked_words_action: config.blocked_words_action,
        emit_blocked_words_events: config.emit_blocked_words_events,
        system_messages: config.system_messages,
        replace_signals_on_message_submit: config.replace_signals_on_message_submit,
        message_insert_position: config.message_insert_position,
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
