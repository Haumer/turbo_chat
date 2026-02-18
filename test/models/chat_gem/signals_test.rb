require_relative "../../test_helper"

module ChatGem
  class SignalsTest < ActiveSupport::TestCase
    test "with wraps execution and clears signal" do
      user = User.create!(email: "signals_module@example.com")
      chat = ChatGem::Chat.create!(title: "Signals Module")
      ChatGem::ChatMembership.create!(chat: chat, participant: user)

      ChatGem::Signals.with(chat: chat, participant: user, signal_type: :typing) do
        assert_equal 1, chat.chat_messages.signal.where(participant: user).count
      end

      assert_equal 0, chat.chat_messages.signal.where(participant: user).count
    end
  end
end
