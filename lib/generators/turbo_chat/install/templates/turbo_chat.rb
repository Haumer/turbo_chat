TurboChat.configure do |config|
  # Permissions
  config.permission_adapter = TurboChat::Permission
  # Class that answers permission checks for participants/chats.

  # Authentication
  # config.current_participant_resolver = ->(controller) { controller.send(:current_member) }
  # Fallback resolver when you do not define `current_chat_participant`.

  # Limits
  config.max_chat_participants = 10
  # Maximum active members allowed in a chat.
  config.max_message_length = 1000
  # Maximum characters allowed in a message body.
  config.message_history_limit = 200
  # Number of recent messages loaded in chat history.
  config.active_chat_window = 5.minutes
  # Duration used to classify chats as active.

  # Mentions and emoji
  config.enable_mentions = true
  # Enables mention parsing/highlighting and mention UI.
  config.mention_filter_exclude_self = true
  # Hides self from mention suggestions.
  config.mention_filter_hide_roles = true
  # Hides @ROLE suggestions in mention picker.
  config.enable_emoji_aliases = true
  # Expands :alias: tokens using configured emoji aliases.
  config.emoji_aliases = TurboChat::Configuration::DEFAULT_EMOJI_ALIASES.dup
  # Hash of emoji alias mappings, e.g. "smile" => "😄".

  # Blocked words
  config.blocked_words = []
  # Case-insensitive word list checked before message save.
  config.blocked_words_action = :reject
  # `:reject` adds a validation error, `:scramble` rewrites matched words.
  config.blocked_words_scramble_chars = TurboChat::Configuration::DEFAULT_BLOCKED_WORDS_SCRAMBLE_CHARS.dup
  # Character pool used when scrambling blocked words.

  # Visuals
  # config.mention_mark_hex_color = "b42318"
  # Mention highlight color (without #).
  # config.mention_highlight_hex_color = "b42318"
  # Legacy mention highlight color fallback.
  # config.own_message_hex_color = "eef6ff"
  # Bubble background color for current participant messages.
  # config.other_message_hex_color = "ffffff"
  # Bubble background color for other participant messages.
  config.role_message_hex_colors = {}
  # Map role key to message bubble color.
  config.show_timestamp = true
  # Shows formatted timestamp on each message.
  # config.show_role = true
  # Shows participant role label near messages.
  config.show_members = true
  # Shows member list panel in chat UI.
  config.system_messages = true
  # Shows system timeline messages (joins, invites, moderation).
  config.message_source_labels = TurboChat::Configuration::DEFAULT_MESSAGE_SOURCE_LABELS.dup
  # Maps message source keys to labels shown on non-default source badges.
  config.chat_style = "chat_style_bounded"
  # Chat layout style: `chat_style_bounded` or `chat_style_unbounded`.
  config.composer_placeholder_text = "start chatting"
  # Placeholder text for the message composer input.

  # Optional composer controls (disabled by default)
  # config.composer_add_files_display = true
  # Shows the add-files control in the composer.
  # config.composer_add_files_active = true
  # Enables add-files control interaction.
  # config.composer_microphone_display = true
  # Shows microphone control in composer.
  # config.composer_microphone_active = true
  # Enables microphone control interaction.

  # Optional browser events (disabled by default)
  # config.emit_typing_events = true
  # Emits `turbo-chat:typing-started` and `turbo-chat:typing-ended`.
  # config.emit_message_events = true
  # Emits `turbo-chat:message-sent`.
  # config.emit_mention_events = true
  # Emits `turbo-chat:mention`.
  # config.emit_invitation_events = true
  # Emits `turbo-chat:invitation-accepted`.
  # config.emit_chat_lifecycle_events = true
  # Emits `turbo-chat:chat-*` lifecycle events.

  # Optional ActiveSupport::Notifications events (disabled by default)
  # config.emit_moderation_events = true
  # Emits `turbo_chat.moderation.*` notifications.
  # config.emit_blocked_words_events = true
  # Emits `turbo_chat.blocked_words.*` notifications.

  # Signal behavior
  config.signal_ttl_seconds = 60
  # Maximum age (in seconds) for active typing/signal indicators.
  config.signal_text_sheen = true
  # Adds bracketed sheen styling to custom signal text.
  # Optional toggles (disabled by default)
  # config.show_self_signals = true
  # Shows your own active typing/signal indicators.
  # config.replace_signals_on_message_submit = true
  # Replaces existing signals when sending a message.

  # Optional message rendering hooks
  # config.message_css_class_resolver = ->(_chat_message) { "chat-message" }
  # Returns extra CSS class names for a message wrapper.
  # config.render_message_html = true
  # Renders/sanitizes HTML in message bodies.
  config.message_html_tags = %w[a b br code em i li ol p pre strong ul]
  # Allowed HTML tags when `render_message_html` is true.
  config.message_html_attributes = %w[href target rel class]
  # Allowed HTML attributes when `render_message_html` is true.
  config.timestamp_formatter = ->(timestamp, _chat_message) { I18n.l(timestamp.in_time_zone, format: :long) }
  # Formatter lambda for displayed timestamps.
  config.role_formatter = ->(role, _chat_message) { role.to_s.humanize }
  # Formatter lambda for displayed role labels.
end
