require "test_helper"

class ChatFlowTest < ActionDispatch::IntegrationTest
  test "renders chats index and shows a chat" do
    user = User.create!(email: "integration@example.com")
    chat = ChatGem::Chat.create!(title: "Integration Chat")
    ChatGem::ChatMembership.create!(chat: chat, participant: user)
    ChatGem::ChatMessage.create!(chat: chat, participant: user, body: "hello", kind: :message)

    get "/chat/chats"
    assert_response :success
    assert_includes response.body, "Integration Chat"

    get "/chat/chats/#{chat.id}"
    assert_response :success
    assert_includes response.body, "hello"
  end

  test "chat show includes turbo and actioncable wiring for live updates" do
    user = User.create!(email: "wiring@example.com")
    chat = ChatGem::Chat.create!(title: "Wiring Chat")
    ChatGem::ChatMembership.create!(chat: chat, participant: user)

    get "/chat/chats/#{chat.id}"
    assert_response :success

    assert_includes response.body, "action-cable-url"
    assert_match(/turbo/i, response.body)
    assert_includes response.body, "turbo-cable-stream-source"
  end

  test "requires chat_current_participant to return an acts_as_chat_participant model" do
    original_method = ApplicationController.instance_method(:chat_current_participant)
    ApplicationController.send(:define_method, :chat_current_participant) { "not-a-model" }

    error = assert_raises(ArgumentError) do
      get "/chat/chats"
    end

    assert_includes error.message, "acts_as_chat_participant"
  ensure
    ApplicationController.send(:define_method, :chat_current_participant, original_method)
  end
end
