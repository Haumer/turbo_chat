require_relative "../test_helper"

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

  test "chats index falls back when invitation migration is not yet applied" do
    user = User.create!(email: "legacy-index@example.com")
    chat = ChatGem::Chat.create!(title: "Legacy Index Chat")
    ChatGem::ChatMembership.create!(chat: chat, participant: user)

    ChatGem::ChatMembership.stub(:invitation_tracking_supported?, false) do
      get "/chat/chats"
      assert_response :success
      assert_includes response.body, "Legacy Index Chat"
      assert_not_includes response.body, "Pending Invitations"
    end
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
    assert_includes response.body, "/javascripts/chat_gem/shared.js"
    assert_includes response.body, "/javascripts/chat_gem/messages.js"
    assert_includes response.body, "/javascripts/chat_gem/realtime.js"
    assert_includes response.body, "/javascripts/chat_gem/lifecycle_events.js"
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

  test "chat show hides the current participant signal by default" do
    current_user = User.create!(email: "self-signal@example.com")
    other_user = User.create!(email: "other-signal@example.com")
    chat = ChatGem::Chat.create!(title: "Signals Chat")

    ChatGem::ChatMembership.create!(chat: chat, participant: current_user)
    ChatGem::ChatMembership.create!(chat: chat, participant: other_user)
    ChatGem::ChatMessage.create!(chat: chat, participant: current_user, kind: :signal, signal_type: :typing)
    ChatGem::ChatMessage.create!(chat: chat, participant: other_user, kind: :signal, signal_type: :typing)

    get "/chat/chats/#{chat.id}"
    assert_response :success

    assert_includes response.body, %(data-chat-show-self-signals="false")
    assert_select "#signals_chat_#{chat.id} strong", text: other_user.email, count: 1
    assert_select "#signals_chat_#{chat.id} strong", text: current_user.email, count: 0
  end

  test "chat show can include the current participant signal when configured" do
    previous_value = ChatGem.configuration.show_self_signals
    ChatGem.configuration.show_self_signals = true

    current_user = User.create!(email: "self-visible@example.com")
    chat = ChatGem::Chat.create!(title: "Visible Signal Chat")

    ChatGem::ChatMembership.create!(chat: chat, participant: current_user)
    ChatGem::ChatMessage.create!(chat: chat, participant: current_user, kind: :signal, signal_type: :typing)

    get "/chat/chats/#{chat.id}"
    assert_response :success

    assert_includes response.body, %(data-chat-show-self-signals="true")
    assert_includes response.body, current_user.email
  ensure
    ChatGem.configuration.show_self_signals = previous_value
  end

  test "chat show applies custom message css classes from resolver" do
    previous_resolver = ChatGem.configuration.message_css_class_resolver
    ChatGem.configuration.message_css_class_resolver = lambda { |_chat_message, own_message|
      own_message ? "chat-bubble--mine-custom" : "chat-bubble--theirs-custom"
    }

    user = User.create!(email: "styling-owner@example.com")
    other = User.create!(email: "styling-other@example.com")
    chat = ChatGem::Chat.create!(title: "Styling Chat")

    ChatGem::ChatMembership.create!(chat: chat, participant: user)
    ChatGem::ChatMembership.create!(chat: chat, participant: other)
    ChatGem::ChatMessage.create!(chat: chat, participant: user, body: "owner message", kind: :message)
    ChatGem::ChatMessage.create!(chat: chat, participant: other, body: "other message", kind: :message)

    get "/chat/chats/#{chat.id}"
    assert_response :success

    assert_includes response.body, "chat-bubble--mine-custom"
    assert_includes response.body, "chat-bubble--theirs-custom"
  ensure
    ChatGem.configuration.message_css_class_resolver = previous_resolver
  end

  test "chat show exposes and applies ownership metadata for current participant" do
    current_user = User.create!(email: "owner-view@example.com")
    other_user = User.create!(email: "other-view@example.com")
    chat = ChatGem::Chat.create!(title: "Ownership Chat")

    ChatGem::ChatMembership.create!(chat: chat, participant: current_user)
    ChatGem::ChatMembership.create!(chat: chat, participant: other_user)
    ChatGem::ChatMessage.create!(chat: chat, participant: current_user, body: "my message", kind: :message)
    ChatGem::ChatMessage.create!(chat: chat, participant: other_user, body: "their message", kind: :message)

    get "/chat/chats/#{chat.id}"
    assert_response :success

    assert_select ".chat-messages[data-chat-self-participant-type='User'][data-chat-self-participant-id='#{current_user.id}']", 1
    assert_select ".chat-bubble[data-chat-message-participant-type='User'][data-chat-message-participant-id='#{current_user.id}']", 1
    assert_select ".chat-bubble[data-chat-message-participant-type='User'][data-chat-message-participant-id='#{other_user.id}']", 1
    assert_select ".chat-bubble--own[data-chat-message-participant-type='User'][data-chat-message-participant-id='#{current_user.id}']", 1
    assert_select ".chat-bubble--own[data-chat-message-participant-type='User'][data-chat-message-participant-id='#{other_user.id}']", 0
  end

  test "chat show exposes mention metadata for frontend mention highlighting and events" do
    previous_emit_mentions = ChatGem.configuration.emit_mention_events
    previous_mention_mark = ChatGem.configuration.mention_mark_hex_color
    previous_mention_highlight = ChatGem.configuration.mention_highlight_hex_color

    ChatGem.configuration.emit_mention_events = true
    ChatGem.configuration.mention_mark_hex_color = "#cf1322"

    current_user = User.create!(email: "mention-metadata-current@example.com")
    other_user = User.create!(email: "mention-metadata-other@example.com")
    chat = ChatGem::Chat.create!(title: "Mention Metadata")

    ChatGem::ChatMembership.create!(chat: chat, participant: current_user, role: :member)
    ChatGem::ChatMembership.create!(chat: chat, participant: other_user, role: :member)
    ChatGem::ChatMessage.create!(chat: chat, participant: other_user, body: "hello @mention_metadata_current", kind: :message)

    get "/chat/chats/#{chat.id}"
    assert_response :success

    assert_select ".chat-messages[data-chat-emit-mention-events='true'][data-chat-mention-filter-exclude-self='true'][data-chat-mention-filter-hide-roles='true']", 1
    assert_select ".chat-messages[data-chat-self-mention-tokens]", 1
    assert_includes response.body, "--chat-mention-highlight-color: #cf1322; --chat-mention-mark-background: #cf132238;"
    assert_select ".chat-bubble[data-chat-message-mentions]", 1
  ensure
    ChatGem.configuration.emit_mention_events = previous_emit_mentions
    ChatGem.configuration.mention_mark_hex_color = previous_mention_mark
    ChatGem.configuration.mention_highlight_hex_color = previous_mention_highlight
  end

  test "chat show escapes html in message body by default" do
    user = User.create!(email: "html-default@example.com")
    chat = ChatGem::Chat.create!(title: "HTML Default")
    ChatGem::ChatMembership.create!(chat: chat, participant: user)
    ChatGem::ChatMessage.create!(chat: chat, participant: user, kind: :message, body: "<strong>bold</strong>")

    get "/chat/chats/#{chat.id}"
    assert_response :success

    assert_includes response.body, "&lt;strong&gt;bold&lt;/strong&gt;"
    assert_not_includes response.body, "<strong>bold</strong>"
  end

  test "chat show renders sanitized html when enabled" do
    previous_render_html = ChatGem.configuration.render_message_html

    ChatGem.configuration.render_message_html = true

    user = User.create!(email: "html-enabled@example.com")
    chat = ChatGem::Chat.create!(title: "HTML Enabled")
    ChatGem::ChatMembership.create!(chat: chat, participant: user)
    ChatGem::ChatMessage.create!(
      chat: chat,
      participant: user,
      kind: :message,
      body: "<strong>bold</strong><script>alert('x')</script>"
    )

    get "/chat/chats/#{chat.id}"
    assert_response :success

    assert_includes response.body, "<strong>bold</strong>"
    assert_not_includes response.body, "<script>"
  ensure
    ChatGem.configuration.render_message_html = previous_render_html
  end

  test "chat show uses message history limit" do
    previous_limit = ChatGem.configuration.message_history_limit
    ChatGem.configuration.message_history_limit = 2

    user = User.create!(email: "history-limit@example.com")
    chat = ChatGem::Chat.create!(title: "History Limit")
    ChatGem::ChatMembership.create!(chat: chat, participant: user)
    ChatGem::ChatMessage.create!(chat: chat, participant: user, kind: :message, body: "history-oldest", created_at: 3.minutes.ago)
    ChatGem::ChatMessage.create!(chat: chat, participant: user, kind: :message, body: "history-middle", created_at: 2.minutes.ago)
    ChatGem::ChatMessage.create!(chat: chat, participant: user, kind: :message, body: "history-newest", created_at: 1.minute.ago)

    get "/chat/chats/#{chat.id}"
    assert_response :success

    assert_not_includes response.body, "history-oldest"
    assert_includes response.body, "history-middle"
    assert_includes response.body, "history-newest"
  ensure
    ChatGem.configuration.message_history_limit = previous_limit
  end

  test "chat message partial renders with application controller renderer" do
    participant = User.create!(email: "renderer@example.com")
    chat = ChatGem::Chat.create!(title: "Renderer Chat")
    ChatGem::ChatMembership.create!(chat: chat, participant: participant, role: :member)
    chat_message = ChatGem::ChatMessage.create!(
      chat: chat,
      participant: participant,
      kind: :message,
      body: "renderer message",
      created_at: Time.current
    )

    rendered = ApplicationController.render(
      partial: "chat_gem/chat_messages/message",
      locals: { chat_message: chat_message }
    )

    assert_includes rendered, "chat-bubble"
    assert_includes rendered, "renderer message"
    assert_includes rendered, %(data-chat-message-participant-type="User")
    assert_includes rendered, %(data-chat-message-participant-id="#{participant.id}")
  end

end
