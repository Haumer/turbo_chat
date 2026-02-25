class TurboChat::Configuration
  DEFAULT_ROLE_DEFINITIONS = {
    "member" => {
      name: "Member",
      rank: 0,
      permissions: %i[view_chat post_message mention_member]
    },
    "moderator" => {
      name: "Moderator",
      rank: 1,
      permissions: %i[
        view_chat post_message mention_member mention_all mention_role
        invite_member mute_member timeout_member ban_member delete_message
      ]
    },
    "admin" => {
      name: "Admin",
      rank: 2,
      permissions: %i[
        view_chat post_message mention_member mention_all mention_role
        invite_member mute_member timeout_member ban_member delete_message
        close_chat reopen_chat grant_member_permissions
      ]
    }
  }.freeze

  DEFAULT_MESSAGE_HTML_TAGS = %w[a b br code em i li ol p pre strong ul].freeze
  DEFAULT_MESSAGE_HTML_ATTRIBUTES = %w[href target rel class].freeze
  DEFAULT_EMOJI_ALIASES = {
    "smile" => "😄",
    "grin" => "😁",
    "laughing" => "😆",
    "blush" => "😊",
    "wink" => "😉",
    "heart" => "❤️",
    "thumbsup" => "👍",
    "+1" => "👍",
    "thumbsdown" => "👎",
    "-1" => "👎",
    "fire" => "🔥",
    "rocket" => "🚀",
    "thinking" => "🤔",
    "tada" => "🎉",
    "wave" => "👋",
    "eyes" => "👀"
  }.freeze
  DEFAULT_BLOCKED_WORDS_SCRAMBLE_CHARS = %w[# * / ( = ) ! 8].freeze
  DEFAULT_BLOCKED_WORDS_ACTION = "reject".freeze
  DEFAULT_MESSAGE_SOURCE_LABELS = {
    "app" => "App",
    "whatsapp" => "WhatsApp"
  }.freeze

  DEFAULTS = {
    permission_adapter: -> { TurboChat::Permission },
    current_participant_resolver: nil,
    max_chat_participants: 10,
    max_message_length: 1000,
    message_history_limit: 200,
    enable_mentions: true,
    mention_filter_exclude_self: true,
    mention_filter_hide_roles: true,
    enable_emoji_aliases: true,
    emoji_aliases: -> { DEFAULT_EMOJI_ALIASES.dup },
    blocked_words: -> { [] },
    blocked_words_action: DEFAULT_BLOCKED_WORDS_ACTION,
    blocked_words_scramble_chars: -> { DEFAULT_BLOCKED_WORDS_SCRAMBLE_CHARS.dup },
    mention_mark_hex_color: nil,
    mention_highlight_hex_color: nil,
    own_message_hex_color: nil,
    other_message_hex_color: nil,
    role_message_hex_colors: -> { {} },
    show_timestamp: true,
    show_role: false,
    show_members: true,
    system_messages: true,
    composer_placeholder_text: "start chatting",
    composer_add_files_display: false,
    composer_add_files_active: false,
    composer_microphone_display: false,
    composer_microphone_active: false,
    active_chat_window: -> { 5.minutes },
    emit_typing_events: false,
    emit_message_events: false,
    emit_mention_events: false,
    emit_invitation_events: false,
    emit_chat_lifecycle_events: false,
    emit_moderation_events: false,
    emit_blocked_words_events: false,
    signal_text_sheen: true,
    show_self_signals: false,
    replace_signals_on_message_submit: false,
    message_css_class_resolver: nil,
    message_source_labels: -> { DEFAULT_MESSAGE_SOURCE_LABELS.dup },
    chat_style: "chat_style_bounded",
    render_message_html: false,
    message_html_tags: -> { DEFAULT_MESSAGE_HTML_TAGS.dup },
    message_html_attributes: -> { DEFAULT_MESSAGE_HTML_ATTRIBUTES.dup },
    timestamp_formatter: -> { ->(timestamp, _chat_message = nil) { I18n.l(timestamp.in_time_zone, format: :long) } },
    role_formatter: -> { ->(role, _chat_message = nil) { role.to_s.humanize } }
  }.freeze
end
