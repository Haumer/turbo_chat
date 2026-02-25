require_relative "../test_helper"

class ChatFlowTest < ActionDispatch::IntegrationTest
  test "renders chats index and shows a chat" do
    user = User.create!(email: "integration@example.com")
    teammate = User.create!(email: "integration-teammate@example.com")
    chat = TurboChat::Chat.create!(title: "Integration Chat")
    TurboChat::ChatMembership.create!(chat: chat, participant: user)
    TurboChat::ChatMembership.create!(chat: chat, participant: teammate)
    TurboChat::ChatMessage.create!(chat: chat, participant: user, body: "hello", kind: :message)

    get "/chat/chats"
    assert_response :success
    assert_includes response.body, "Integration Chat"
    assert_includes response.body, "2 members"

    get "/chat/chats/#{chat.id}"
    assert_response :success
    assert_includes response.body, "hello"
    assert_includes response.body, "Members"
    assert_includes response.body, teammate.email
  end

  test "chat show uses bounded style class by default" do
    user = User.create!(email: "bounded-style@example.com")
    chat = TurboChat::Chat.create!(title: "Bounded Style Chat")
    TurboChat::ChatMembership.create!(chat: chat, participant: user)

    get "/chat/chats/#{chat.id}"
    assert_response :success
    assert_select ".chat-shell.chat-shell--style-bounded[data-chat-style='chat_style_bounded']", 1
  end

  test "chat show supports unbounded style class from configuration" do
    previous_chat_style = TurboChat.configuration.chat_style
    TurboChat.configuration.chat_style = "chat_style_unbounded"

    user = User.create!(email: "unbounded-style@example.com")
    chat = TurboChat::Chat.create!(title: "Unbounded Style Chat")
    TurboChat::ChatMembership.create!(chat: chat, participant: user)

    get "/chat/chats/#{chat.id}"
    assert_response :success
    assert_select ".chat-shell.chat-shell--style-unbounded[data-chat-style='chat_style_unbounded']", 1
  ensure
    TurboChat.configuration.chat_style = previous_chat_style
  end

  test "chat show renders system messages in dedicated system style" do
    user = User.create!(email: "system-style@example.com")
    chat = TurboChat::Chat.create!(title: "System Style Chat")
    TurboChat::ChatMembership.create!(chat: chat, participant: user)
    TurboChat::ChatMessage.create!(chat: chat, participant: user, body: "#{user.email} invited teammate@example.com.", kind: :system)

    get "/chat/chats/#{chat.id}"
    assert_response :success
    assert_select ".chat-system-message", 1
    assert_includes response.body, "invited teammate@example.com."
  end

  test "chat show renders external source badge labels for non-default sources" do
    user = User.create!(email: "source-badge@example.com")
    chat = TurboChat::Chat.create!(title: "Source Badge Chat")
    TurboChat::ChatMembership.create!(chat: chat, participant: user)

    TurboChat::ChatMessage.create!(chat: chat, participant: user, body: "app message", kind: :message)
    TurboChat::ChatMessage.create!(
      chat: chat,
      participant: user,
      body: "external message",
      kind: :message,
      source: "whatsapp"
    )

    get "/chat/chats/#{chat.id}"
    assert_response :success

    assert_select ".chat-meta__source[data-chat-message-source='whatsapp']", text: "WhatsApp", count: 1
    assert_select ".chat-meta__source", count: 1
  end

  test "chat members render in a collapsed panel with fixed-height list shell" do
    user = User.create!(email: "members-panel-user@example.com")
    teammate = User.create!(email: "members-panel-teammate@example.com")
    chat = TurboChat::Chat.create!(title: "Members Panel Chat")
    TurboChat::ChatMembership.create!(chat: chat, participant: user)
    TurboChat::ChatMembership.create!(chat: chat, participant: teammate)

    get "/chat/chats/#{chat.id}"
    assert_response :success

    assert_select ".chat-members details.chat-members-panel:not([open])", 1
    assert_select ".chat-members .chat-members-list-shell", 1
    assert_select ".chat-members [data-chat-member-list='true'][data-chat-id='#{chat.id}']", 1
  end

  test "chat members can be hidden via configuration" do
    previous_show_members = TurboChat.configuration.show_members
    TurboChat.configuration.show_members = false

    user = User.create!(email: "hidden-members@example.com")
    teammate = User.create!(email: "hidden-members-teammate@example.com")
    chat = TurboChat::Chat.create!(title: "Hidden Members Chat")
    TurboChat::ChatMembership.create!(chat: chat, participant: user)
    TurboChat::ChatMembership.create!(chat: chat, participant: teammate)

    get "/chat/chats"
    assert_response :success
    assert_select ".chat-list-meta", 0

    get "/chat/chats/#{chat.id}"
    assert_response :success
    assert_select ".chat-members", 0
  ensure
    TurboChat.configuration.show_members = previous_show_members
  end

  test "composer add files and microphone buttons are hidden by default" do
    previous_placeholder = TurboChat.configuration.composer_placeholder_text
    previous_add_display = TurboChat.configuration.composer_add_files_display
    previous_add_active = TurboChat.configuration.composer_add_files_active
    previous_microphone_display = TurboChat.configuration.composer_microphone_display
    previous_microphone_active = TurboChat.configuration.composer_microphone_active

    TurboChat.configuration.composer_placeholder_text = "start chatting"
    TurboChat.configuration.composer_add_files_display = false
    TurboChat.configuration.composer_add_files_active = false
    TurboChat.configuration.composer_microphone_display = false
    TurboChat.configuration.composer_microphone_active = false

    user = User.create!(email: "composer-hidden@example.com")
    chat = TurboChat::Chat.create!(title: "Composer Hidden Buttons")
    TurboChat::ChatMembership.create!(chat: chat, participant: user)

    get "/chat/chats/#{chat.id}"
    assert_response :success

    assert_select "button.chat-composer-tool--add", 0
    assert_select "button.chat-composer-tool--voice", 0
    assert_select ".chat-composer-shell.chat-composer-shell--no-leading-tool", 1
    assert_includes response.body, %(placeholder="start chatting")
  ensure
    TurboChat.configuration.composer_placeholder_text = previous_placeholder
    TurboChat.configuration.composer_add_files_display = previous_add_display
    TurboChat.configuration.composer_add_files_active = previous_add_active
    TurboChat.configuration.composer_microphone_display = previous_microphone_display
    TurboChat.configuration.composer_microphone_active = previous_microphone_active
  end

  test "composer add files and microphone buttons can render as inactive controls" do
    previous_placeholder = TurboChat.configuration.composer_placeholder_text
    previous_add_display = TurboChat.configuration.composer_add_files_display
    previous_add_active = TurboChat.configuration.composer_add_files_active
    previous_microphone_display = TurboChat.configuration.composer_microphone_display
    previous_microphone_active = TurboChat.configuration.composer_microphone_active

    TurboChat.configuration.composer_placeholder_text = "Say hi"
    TurboChat.configuration.composer_add_files_display = true
    TurboChat.configuration.composer_add_files_active = false
    TurboChat.configuration.composer_microphone_display = true
    TurboChat.configuration.composer_microphone_active = false

    user = User.create!(email: "composer-inactive@example.com")
    chat = TurboChat::Chat.create!(title: "Composer Inactive Buttons")
    TurboChat::ChatMembership.create!(chat: chat, participant: user)

    get "/chat/chats/#{chat.id}"
    assert_response :success

    assert_select "button.chat-composer-tool--add[disabled][aria-disabled='true']", 1
    assert_select "button.chat-composer-tool--voice[disabled][aria-disabled='true']", 1
    assert_select ".chat-composer-shell.chat-composer-shell--no-leading-tool", 0
    assert_includes response.body, %(placeholder="Say hi")
  ensure
    TurboChat.configuration.composer_placeholder_text = previous_placeholder
    TurboChat.configuration.composer_add_files_display = previous_add_display
    TurboChat.configuration.composer_add_files_active = previous_add_active
    TurboChat.configuration.composer_microphone_display = previous_microphone_display
    TurboChat.configuration.composer_microphone_active = previous_microphone_active
  end

  test "chats index falls back when invitation migration is not yet applied" do
    user = User.create!(email: "legacy-index@example.com")
    chat = TurboChat::Chat.create!(title: "Legacy Index Chat")
    TurboChat::ChatMembership.create!(chat: chat, participant: user)

    TurboChat::ChatMembership.stub(:invitation_tracking_supported?, false) do
      get "/chat/chats"
      assert_response :success
      assert_includes response.body, "Legacy Index Chat"
      assert_not_includes response.body, "Pending Invitations"
    end
  end

  test "chat show includes turbo and actioncable wiring for live updates" do
    user = User.create!(email: "wiring@example.com")
    chat = TurboChat::Chat.create!(title: "Wiring Chat")
    TurboChat::ChatMembership.create!(chat: chat, participant: user)

    get "/chat/chats/#{chat.id}"
    assert_response :success

    assert_includes response.body, "action-cable-url"
    assert_match(/turbo/i, response.body)
    assert_includes response.body, "turbo-cable-stream-source"
    assert_match %r{/(?:assets|javascripts)/turbo_chat/shared(?:-[0-9a-f]+)?\.js}, response.body
    assert_match %r{/(?:assets|javascripts)/turbo_chat/messages(?:-[0-9a-f]+)?\.js}, response.body
    assert_match %r{/(?:assets|javascripts)/turbo_chat/realtime(?:-[0-9a-f]+)?\.js}, response.body
    assert_match %r{/(?:assets|javascripts)/turbo_chat/invite_picker(?:-[0-9a-f]+)?\.js}, response.body
    assert_match %r{/(?:assets|javascripts)/turbo_chat/lifecycle_events(?:-[0-9a-f]+)?\.js}, response.body
  end

  test "admin chat show renders searchable invite controls" do
    admin = User.create!(email: "invite-controls-admin@example.com")
    invitee = User.create!(email: "invite-controls-target@example.com")
    chat = TurboChat::Chat.create!(title: "Invite Controls Chat")
    TurboChat::ChatMembership.create!(chat: chat, participant: admin, role: :admin)

    get "/chat/chats/#{chat.id}"
    assert_response :success
    assert_select "section.chat-members .chat-members-invite", 1
    assert_select "form.chat-form--invite[data-chat-invite-form='true']", 1
    assert_select "input.chat-invite-search[data-chat-invite-query-input='true']", 1
    assert_select "input[type='hidden'][name='chat_membership[participant_id]'][data-chat-invite-participant-id-input='true']", 1
    assert_select "div.chat-invite-menu[data-chat-invite-menu]", 1
    assert_select ".chat-shell.chat-shell--can-manage-member-permissions", 1
    assert_select "button[data-chat-member-manage-toggle]", 1
    assert_select "form[data-chat-member-role-form='true']", 1
    assert_includes response.body, invitee.email
    assert_select "select.chat-invite-select", 0
  end

  test "requires current_chat_participant to return an acts_as_chat_participant model" do
    original_method = ApplicationController.instance_method(:current_chat_participant)
    ApplicationController.send(:define_method, :current_chat_participant) { "not-a-model" }

    error = assert_raises(ArgumentError) do
      get "/chat/chats"
    end

    assert_includes error.message, "acts_as_chat_participant"
  ensure
    ApplicationController.send(:define_method, :current_chat_participant, original_method)
  end

  test "prefers host current_chat_participant when defined" do
    preferred_user = User.create!(email: "preferred-participant@example.com")
    chat = TurboChat::Chat.create!(title: "Preferred Participant Chat")
    TurboChat::ChatMembership.create!(chat: chat, participant: preferred_user)

    original_chat_current = ApplicationController.instance_method(:current_chat_participant)
    ApplicationController.send(:define_method, :current_chat_participant) { preferred_user }

    get "/chat/chats"
    assert_response :success
    assert_includes response.body, "Preferred Participant Chat"
  ensure
    ApplicationController.send(:define_method, :current_chat_participant, original_chat_current) if original_chat_current
  end

  test "falls back to current_user when current_chat_participant is not defined" do
    fallback_user = User.create!(email: "fallback-current-user@example.com")
    chat = TurboChat::Chat.create!(title: "Fallback Current User Chat")
    TurboChat::ChatMembership.create!(chat: chat, participant: fallback_user)

    original_chat_current = ApplicationController.instance_method(:current_chat_participant)
    had_current_user = ApplicationController.method_defined?(:current_user)
    original_current_user = ApplicationController.instance_method(:current_user) if had_current_user

    ApplicationController.send(:undef_method, :current_chat_participant)
    ApplicationController.send(:define_method, :current_user) { fallback_user }

    get "/chat/chats"
    assert_response :success
    assert_includes response.body, "Fallback Current User Chat"
  ensure
    ApplicationController.send(:define_method, :current_chat_participant, original_chat_current) if original_chat_current
    if had_current_user
      ApplicationController.send(:define_method, :current_user, original_current_user)
    elsif ApplicationController.instance_methods(false).include?(:current_user)
      ApplicationController.send(:remove_method, :current_user)
    end
  end

  test "uses configured current participant resolver when controller methods are unavailable" do
    resolver_user = User.create!(email: "resolver-user@example.com")
    chat = TurboChat::Chat.create!(title: "Resolver Participant Chat")
    TurboChat::ChatMembership.create!(chat: chat, participant: resolver_user)

    original_chat_current = ApplicationController.instance_method(:current_chat_participant)
    had_current_user = ApplicationController.method_defined?(:current_user)
    original_current_user = ApplicationController.instance_method(:current_user) if had_current_user
    original_resolver = TurboChat.configuration.current_participant_resolver

    ApplicationController.send(:undef_method, :current_chat_participant)
    ApplicationController.send(:define_method, :current_user) { nil }
    TurboChat.configuration.current_participant_resolver = ->(_controller) { resolver_user }

    get "/chat/chats"
    assert_response :success
    assert_includes response.body, "Resolver Participant Chat"
  ensure
    TurboChat.configuration.current_participant_resolver = original_resolver
    ApplicationController.send(:define_method, :current_chat_participant, original_chat_current) if original_chat_current
    if had_current_user
      ApplicationController.send(:define_method, :current_user, original_current_user)
    elsif ApplicationController.instance_methods(false).include?(:current_user)
      ApplicationController.send(:remove_method, :current_user)
    end
  end

  test "raises helpful error when no participant strategy is available" do
    original_chat_current = ApplicationController.instance_method(:current_chat_participant)
    had_current_user = ApplicationController.method_defined?(:current_user)
    original_current_user = ApplicationController.instance_method(:current_user) if had_current_user
    original_resolver = TurboChat.configuration.current_participant_resolver

    ApplicationController.send(:undef_method, :current_chat_participant)
    ApplicationController.send(:undef_method, :current_user) if had_current_user
    TurboChat.configuration.current_participant_resolver = nil

    error = assert_raises(NotImplementedError) do
      get "/chat/chats"
    end

    assert_includes error.message, "#current_chat_participant"
    assert_includes error.message, "#current_user"
  ensure
    TurboChat.configuration.current_participant_resolver = original_resolver
    ApplicationController.send(:define_method, :current_chat_participant, original_chat_current) if original_chat_current
    if had_current_user
      ApplicationController.send(:define_method, :current_user, original_current_user)
    elsif ApplicationController.instance_methods(false).include?(:current_user)
      ApplicationController.send(:remove_method, :current_user)
    end
  end

  test "chat show hides the current participant signal by default" do
    current_user = User.create!(email: "self-signal@example.com")
    other_user = User.create!(email: "other-signal@example.com")
    chat = TurboChat::Chat.create!(title: "Signals Chat")

    TurboChat::ChatMembership.create!(chat: chat, participant: current_user)
    TurboChat::ChatMembership.create!(chat: chat, participant: other_user)
    TurboChat::ChatMessage.create!(chat: chat, participant: current_user, kind: :signal, signal_type: :typing)
    TurboChat::ChatMessage.create!(chat: chat, participant: other_user, kind: :signal, signal_type: :typing)

    get "/chat/chats/#{chat.id}"
    assert_response :success

    assert_includes response.body, %(data-chat-show-self-signals="false")
    assert_select "#signals_chat_#{chat.id} strong", text: other_user.email, count: 1
    assert_select "#signals_chat_#{chat.id} strong", text: current_user.email, count: 0
  end

  test "chat show can include the current participant signal when configured" do
    previous_value = TurboChat.configuration.show_self_signals
    TurboChat.configuration.show_self_signals = true

    current_user = User.create!(email: "self-visible@example.com")
    chat = TurboChat::Chat.create!(title: "Visible Signal Chat")

    TurboChat::ChatMembership.create!(chat: chat, participant: current_user)
    TurboChat::ChatMessage.create!(chat: chat, participant: current_user, kind: :signal, signal_type: :typing)

    get "/chat/chats/#{chat.id}"
    assert_response :success

    assert_includes response.body, %(data-chat-show-self-signals="true")
    assert_includes response.body, current_user.email
  ensure
    TurboChat.configuration.show_self_signals = previous_value
  end

  test "chat show renders custom signal text" do
    current_user = User.create!(email: "custom-signal-self@example.com")
    other_user = User.create!(email: "custom-signal-other@example.com")
    chat = TurboChat::Chat.create!(title: "Custom Signal Chat")

    TurboChat::ChatMembership.create!(chat: chat, participant: current_user)
    TurboChat::ChatMembership.create!(chat: chat, participant: other_user)
    TurboChat::Signals.start!(
      chat: chat,
      participant: other_user,
      signal_type: :custom,
      signal_text: "Reviewing your request"
    )

    get "/chat/chats/#{chat.id}"
    assert_response :success

    assert_select "#signals_chat_#{chat.id} strong", text: other_user.email, count: 1
    assert_select "#signals_chat_#{chat.id} .chat-signal-text.chat-signal-text--sheen", text: "Reviewing your request", count: 1
    assert_select "#signals_chat_#{chat.id} .chat-signal-text.chat-signal-text--sheen .chat-signal-text-sheen", text: "Reviewing your request", count: 1
  end

  test "chat show can disable custom signal text sheen styling" do
    previous_value = TurboChat.configuration.signal_text_sheen
    TurboChat.configuration.signal_text_sheen = false

    current_user = User.create!(email: "custom-signal-no-sheen-self@example.com")
    other_user = User.create!(email: "custom-signal-no-sheen-other@example.com")
    chat = TurboChat::Chat.create!(title: "Custom Signal No Sheen Chat")

    TurboChat::ChatMembership.create!(chat: chat, participant: current_user)
    TurboChat::ChatMembership.create!(chat: chat, participant: other_user)
    TurboChat::Signals.start!(
      chat: chat,
      participant: other_user,
      signal_type: :custom,
      signal_text: "Reviewing your request"
    )

    get "/chat/chats/#{chat.id}"
    assert_response :success

    assert_select "#signals_chat_#{chat.id} .chat-signal-text", text: "Reviewing your request", count: 1
    assert_select "#signals_chat_#{chat.id} .chat-signal-text--sheen", count: 0
    assert_select "#signals_chat_#{chat.id} .chat-signal-text-sheen", count: 0
  ensure
    TurboChat.configuration.signal_text_sheen = previous_value
  end

  test "chat show applies custom message css classes from resolver" do
    previous_resolver = TurboChat.configuration.message_css_class_resolver
    TurboChat.configuration.message_css_class_resolver = lambda { |_chat_message, own_message|
      own_message ? "chat-bubble--mine-custom" : "chat-bubble--theirs-custom"
    }

    user = User.create!(email: "styling-owner@example.com")
    other = User.create!(email: "styling-other@example.com")
    chat = TurboChat::Chat.create!(title: "Styling Chat")

    TurboChat::ChatMembership.create!(chat: chat, participant: user)
    TurboChat::ChatMembership.create!(chat: chat, participant: other)
    TurboChat::ChatMessage.create!(chat: chat, participant: user, body: "owner message", kind: :message)
    TurboChat::ChatMessage.create!(chat: chat, participant: other, body: "other message", kind: :message)

    get "/chat/chats/#{chat.id}"
    assert_response :success

    assert_includes response.body, "chat-bubble--mine-custom"
    assert_includes response.body, "chat-bubble--theirs-custom"
  ensure
    TurboChat.configuration.message_css_class_resolver = previous_resolver
  end

  test "chat show exposes and applies ownership metadata for current participant" do
    current_user = User.create!(email: "owner-view@example.com")
    other_user = User.create!(email: "other-view@example.com")
    chat = TurboChat::Chat.create!(title: "Ownership Chat")

    TurboChat::ChatMembership.create!(chat: chat, participant: current_user)
    TurboChat::ChatMembership.create!(chat: chat, participant: other_user)
    TurboChat::ChatMessage.create!(chat: chat, participant: current_user, body: "my message", kind: :message)
    TurboChat::ChatMessage.create!(chat: chat, participant: other_user, body: "their message", kind: :message)

    get "/chat/chats/#{chat.id}"
    assert_response :success

    assert_select ".chat-messages[data-chat-self-participant-type='User'][data-chat-self-participant-id='#{current_user.id}']", 1
    assert_select ".chat-bubble[data-chat-message-participant-type='User'][data-chat-message-participant-id='#{current_user.id}']", 1
    assert_select ".chat-bubble[data-chat-message-participant-type='User'][data-chat-message-participant-id='#{other_user.id}']", 1
    assert_select ".chat-bubble--own[data-chat-message-participant-type='User'][data-chat-message-participant-id='#{current_user.id}']", 1
    assert_select ".chat-bubble--own[data-chat-message-participant-type='User'][data-chat-message-participant-id='#{other_user.id}']", 0
  end

  test "chat show exposes mention metadata for frontend mention highlighting and events" do
    previous_emit_mentions = TurboChat.configuration.emit_mention_events
    previous_mention_mark = TurboChat.configuration.mention_mark_hex_color
    previous_mention_highlight = TurboChat.configuration.mention_highlight_hex_color

    TurboChat.configuration.emit_mention_events = true
    TurboChat.configuration.mention_mark_hex_color = "#cf1322"

    current_user = User.create!(email: "mention-metadata-current@example.com")
    other_user = User.create!(email: "mention-metadata-other@example.com")
    chat = TurboChat::Chat.create!(title: "Mention Metadata")

    TurboChat::ChatMembership.create!(chat: chat, participant: current_user, role: :member)
    TurboChat::ChatMembership.create!(chat: chat, participant: other_user, role: :member)
    TurboChat::ChatMessage.create!(chat: chat, participant: other_user, body: "hello @mention_metadata_current", kind: :message)

    get "/chat/chats/#{chat.id}"
    assert_response :success

    assert_select ".chat-messages[data-chat-emit-mention-events='true'][data-chat-mention-filter-exclude-self='true'][data-chat-mention-filter-hide-roles='true']", 1
    assert_select ".chat-messages[data-chat-self-mention-tokens]", 1
    assert_includes response.body, "--chat-mention-highlight-color: #cf1322; --chat-mention-mark-background: #cf132238;"
    assert_select ".chat-bubble[data-chat-message-mentions]", 1
  ensure
    TurboChat.configuration.emit_mention_events = previous_emit_mentions
    TurboChat.configuration.mention_mark_hex_color = previous_mention_mark
    TurboChat.configuration.mention_highlight_hex_color = previous_mention_highlight
  end

  test "chat show escapes html in message body by default" do
    user = User.create!(email: "html-default@example.com")
    chat = TurboChat::Chat.create!(title: "HTML Default")
    TurboChat::ChatMembership.create!(chat: chat, participant: user)
    TurboChat::ChatMessage.create!(chat: chat, participant: user, kind: :message, body: "<strong>bold</strong>")

    get "/chat/chats/#{chat.id}"
    assert_response :success

    assert_includes response.body, "&lt;strong&gt;bold&lt;/strong&gt;"
    assert_not_includes response.body, "<strong>bold</strong>"
  end

  test "chat show renders sanitized html when enabled" do
    previous_render_html = TurboChat.configuration.render_message_html

    TurboChat.configuration.render_message_html = true

    user = User.create!(email: "html-enabled@example.com")
    chat = TurboChat::Chat.create!(title: "HTML Enabled")
    TurboChat::ChatMembership.create!(chat: chat, participant: user)
    TurboChat::ChatMessage.create!(
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
    TurboChat.configuration.render_message_html = previous_render_html
  end

  test "chat show uses message history limit" do
    previous_limit = TurboChat.configuration.message_history_limit
    TurboChat.configuration.message_history_limit = 2

    user = User.create!(email: "history-limit@example.com")
    chat = TurboChat::Chat.create!(title: "History Limit")
    TurboChat::ChatMembership.create!(chat: chat, participant: user)
    TurboChat::ChatMessage.create!(chat: chat, participant: user, kind: :message, body: "history-oldest", created_at: 3.minutes.ago)
    TurboChat::ChatMessage.create!(chat: chat, participant: user, kind: :message, body: "history-middle", created_at: 2.minutes.ago)
    TurboChat::ChatMessage.create!(chat: chat, participant: user, kind: :message, body: "history-newest", created_at: 1.minute.ago)

    get "/chat/chats/#{chat.id}"
    assert_response :success

    assert_not_includes response.body, "history-oldest"
    assert_includes response.body, "history-middle"
    assert_includes response.body, "history-newest"
  ensure
    TurboChat.configuration.message_history_limit = previous_limit
  end

  test "chat message partial renders with application controller renderer" do
    participant = User.create!(email: "renderer@example.com")
    chat = TurboChat::Chat.create!(title: "Renderer Chat")
    TurboChat::ChatMembership.create!(chat: chat, participant: participant, role: :member)
    chat_message = TurboChat::ChatMessage.create!(
      chat: chat,
      participant: participant,
      kind: :message,
      body: "renderer message",
      created_at: Time.current
    )

    rendered = ApplicationController.render(
      partial: "turbo_chat/chat_messages/message",
      locals: { chat_message: chat_message }
    )

    assert_includes rendered, "chat-bubble"
    assert_includes rendered, "renderer message"
    assert_includes rendered, %(data-chat-message-participant-type="User")
    assert_includes rendered, %(data-chat-message-participant-id="#{participant.id}")
  end

end
