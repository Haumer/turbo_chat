require_relative "../../test_helper"

module TurboChat
  class ActsAsChatParticipantTest < ActiveSupport::TestCase
    test "adds participant associations" do
      user = User.create!(email: "participant@example.com")
      chat = TurboChat::Chat.create!(title: "Participant Chat")
      membership = TurboChat::ChatMembership.create!(chat: chat, participant: user)
      message = TurboChat::ChatMessage.create!(chat: chat, participant: user, kind: :message, body: "hello")

      assert_includes user.chat_memberships, membership
      assert_includes user.chat_messages, message
      assert_includes user.chats, chat
      assert user.joined_chat?(chat)
      assert_includes user.active_chat_memberships, membership
    end
  end
end
