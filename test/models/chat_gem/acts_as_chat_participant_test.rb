require_relative "../../test_helper"

module ChatGem
  class ActsAsChatParticipantTest < ActiveSupport::TestCase
    test "adds participant associations" do
      user = User.create!(email: "participant@example.com")
      chat = ChatGem::Chat.create!(title: "Participant Chat")
      membership = ChatGem::ChatMembership.create!(chat: chat, participant: user)
      message = ChatGem::ChatMessage.create!(chat: chat, participant: user, kind: :message, body: "hello")

      assert_includes user.chat_memberships, membership
      assert_includes user.chat_messages, message
      assert_includes user.chats, chat
      assert user.joined_chat?(chat)
      assert_includes user.active_chat_memberships, membership
    end
  end
end
