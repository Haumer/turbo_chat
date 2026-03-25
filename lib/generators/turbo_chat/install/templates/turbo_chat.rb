TurboChat.configure do |config|
  # Chat scope
  config.chat.permission_adapter = TurboChat::Permission
  # Class that answers permission checks for participants/chats.

  # Authentication
  # config.chat.current_participant_resolver = ->(controller) { controller.send(:current_member) }
  # Fallback resolver when you do not define `current_chat_participant`.

  # Chat limits
  config.chat.max_chat_participants = 10
  # Maximum active members allowed in a chat.
  config.chat_message.max_message_length = 1000
  # Maximum characters allowed in a message body.
  config.chat_message.message_history_limit = 200
  # Number of recent messages loaded in chat history.
  config.chat.active_chat_window = 5.minutes
  # Duration used to classify chats as active.
  config.chat.show_members = true
  # Shows member list panel in chat UI.
  config.chat.show_members_list = true
  # Shows member entries list inside the members panel.
  config.chat.show_members_invite_controls = true
  # Shows invite controls in members panel (and in fallback invite area when enabled).
  config.chat.show_invite_fallback_when_members_hidden = true
  # Shows fallback invite area when members panel is hidden.
  config.chat.system_messages = true
  # Shows system timeline messages (joins, invites, moderation).
  # config.chat.disable_input = true
  # Disables composer rendering and blocks message submissions.
  # config.chat.show_header_title = false
  # Hides the chat title in the conversation header.
  # config.chat.show_header_status = false
  # Hides the Open/Closed status tag in the conversation header.
  # config.chat.show_header_close_action = false
  # Hides the Close/Reopen action in the conversation header.
  # config.chat.show_header_leave_action = false
  # Hides the Leave action in the conversation header.
  # config.chat.show_header_back_action = false
  # Hides the Back action in the conversation header.

  # Chat message behavior
  config.chat_message.enable_mentions = true
  # Enables mention parsing/highlighting and mention UI.
  config.chat_message.mention_filter_exclude_self = true
  # Hides self from mention suggestions.
  config.chat_message.mention_filter_hide_roles = true
  # Hides @ROLE suggestions in mention picker.
  config.chat_message.enable_emoji_aliases = true
  # Expands :alias: tokens using configured emoji aliases.
  config.chat_message.emoji_aliases = TurboChat::Configuration::DEFAULT_EMOJI_ALIASES.dup
  # Hash of emoji alias mappings, e.g. "smile" => "😄".

  # Blocked words
  config.chat_message.blocked_words = []
  # Case-insensitive word list checked before message save.
  config.chat_message.blocked_words_action = :reject
  # `:reject` adds a validation error, `:scramble` rewrites matched words.
  config.chat_message.blocked_words_scramble_chars = TurboChat::Configuration::DEFAULT_BLOCKED_WORDS_SCRAMBLE_CHARS.dup
  # Character pool used when scrambling blocked words.
  config.chat_message.message_source_labels = TurboChat::Configuration::DEFAULT_MESSAGE_SOURCE_LABELS.dup
  # Maps message source keys to labels shown on non-default source badges.
  # config.chat_message.message_insert_position = "append_end"
  # Timeline insert behavior: `append_end` (near composer) or `append_start` (top of list).
  # config.chat_message.render_message_html = true
  # Renders/sanitizes HTML in message bodies.
  config.chat_message.message_html_tags = %w[a b br code em i li ol p pre strong ul]
  # Allowed HTML tags when `render_message_html` is true.
  config.chat_message.message_html_attributes = %w[href target rel class]
  # Allowed HTML attributes when `render_message_html` is true.
  config.chat_message.timestamp_formatter = ->(timestamp, _chat_message) { I18n.l(timestamp.in_time_zone, format: :long) }
  # Formatter lambda for displayed timestamps.
  config.chat_message.role_formatter = ->(role, _chat_message) { role.to_s.humanize }
  # Formatter lambda for displayed role labels.

  # Style scope
  # config.style.mention_mark_hex_color = "b42318"
  # Mention highlight color (without #).
  # config.style.mention_highlight_hex_color = "b42318"
  # Legacy mention highlight color fallback.
  # config.style.own_message_hex_color = "eef6ff"
  # Bubble background color for current participant messages.
  # config.style.other_message_hex_color = "ffffff"
  # Bubble background color for other participant messages.
  config.style.role_message_hex_colors = {}
  # Map role key to message bubble color.
  config.style.show_timestamp = true
  # Shows formatted timestamp on each message.
  # config.style.show_role = true
  # Shows participant role label near messages.
  config.style.chat_style = "chat_style_bounded"
  # Chat layout style: `chat_style_bounded` or `chat_style_unbounded`.
  config.style.composer_placeholder_text = "start chatting"
  # Placeholder text for the message composer input.
  config.style.signal_text_sheen = true
  # Adds bracketed sheen styling to custom signal text.
  # config.style.message_css_class_resolver = ->(_chat_message) { "chat-message" }
  # Returns extra CSS class names for a message wrapper.

  # Optional composer controls (disabled by default)
  # config.style.composer_add_files_display = true
  # Shows the add-files control in the composer.
  # config.style.composer_add_files_active = true
  # Enables add-files control interaction.
  # config.style.composer_microphone_display = true
  # Shows microphone control in composer.
  # config.style.composer_microphone_active = true
  # Enables microphone control interaction.

  # Events scope (disabled by default)
  # config.events.emit_typing_events = true
  # Emits `turbo-chat:typing-started` and `turbo-chat:typing-ended`.
  # config.events.emit_message_events = true
  # Emits `turbo-chat:message-sent`.
  # config.events.emit_mention_events = true
  # Emits `turbo-chat:mention`.
  # config.events.emit_invitation_events = true
  # Emits `turbo-chat:invitation-accepted`.
  # config.events.emit_chat_lifecycle_events = true
  # Emits `turbo-chat:chat-*` lifecycle events.

  # Moderation scope (disabled by default)
  # config.moderation.emit_moderation_events = true
  # Emits `turbo_chat.moderation.*` notifications.
  # config.moderation.emit_blocked_words_events = true
  # Emits `turbo_chat.blocked_words.*` notifications.

  # Signals scope
  config.signals.signal_ttl_seconds = 60
  # Maximum age (in seconds) for active typing/signal indicators.
  # Optional toggles (disabled by default)
  # config.signals.show_self_signals = true
  # Shows your own active typing/signal indicators.
  # config.signals.replace_signals_on_message_submit = true
  # Replaces existing signals when sending a message.

  # Chat mode overrides
  # Assistant chats default to a simplified 1:1 profile.
  # Uncomment any of these to customize assistant-mode behavior.
  # config.mode(:assistant).show_members = true
  # config.mode(:assistant).enable_mentions = true
  # config.mode(:assistant).show_header_close_action = true
  # config.mode(:assistant).max_chat_participants = 2
end
