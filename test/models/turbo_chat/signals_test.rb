require_relative "../../test_helper"

module TurboChat
  class SignalsTest < ActiveSupport::TestCase
    test "with wraps execution and clears signal" do
      user = User.create!(email: "signals_module@example.com")
      chat = TurboChat::Chat.create!(title: "Signals Module")
      TurboChat::ChatMembership.create!(chat: chat, participant: user)

      TurboChat::Signals.with(chat: chat, participant: user, signal_type: :typing) do
        assert_equal 1, chat.chat_messages.signal.where(participant: user).count
      end

      assert_equal 0, chat.chat_messages.signal.where(participant: user).count
    end

    test "supports custom signal text" do
      user = User.create!(email: "signals_custom_module@example.com")
      chat = TurboChat::Chat.create!(title: "Signals Custom Module")
      TurboChat::ChatMembership.create!(chat: chat, participant: user)

      signal = TurboChat::Signals.start!(
        chat: chat,
        participant: user,
        signal_type: :custom,
        signal_text: "Hello"
      )

      assert_equal "custom", signal.signal_type
      assert_equal "Hello", signal.signal_text
    end

    test "custom! helper creates a custom signal" do
      user = User.create!(email: "signals_custom_helper@example.com")
      chat = TurboChat::Chat.create!(title: "Signals Custom Helper")
      TurboChat::ChatMembership.create!(chat: chat, participant: user)

      signal = TurboChat::Signals.custom!(chat: chat, participant: user, signal_text: "Reviewing")

      assert_equal "custom", signal.signal_type
      assert_equal "Reviewing", signal.signal_text
    end
  end
end
