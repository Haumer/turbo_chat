module ChatGem
  class Configuration
    DEFAULT_ROLE_DEFINITIONS = {
      "member" => {
        name: "Member",
        rank: 0,
        permissions: %i[view_chat post_message mention_member]
      },
      "moderator" => {
        name: "Moderator",
        rank: 1,
        permissions: %i[view_chat post_message mention_member mention_all mention_role invite_member mute_member timeout_member ban_member delete_message]
      },
      "admin" => {
        name: "Admin",
        rank: 2,
        permissions: %i[view_chat post_message mention_member mention_all mention_role invite_member mute_member timeout_member ban_member delete_message close_chat reopen_chat]
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

    attr_accessor :permission_adapter,
                  :max_chat_participants,
                  :max_message_length,
                  :message_history_limit,
                  :enable_mentions,
                  :mention_filter_exclude_self,
                  :mention_filter_hide_roles,
                  :enable_emoji_aliases,
                  :emoji_aliases,
                  :blocked_words,
                  :blocked_words_action,
                  :blocked_words_scramble_chars,
                  :mention_mark_hex_color,
                  :mention_highlight_hex_color,
                  :own_message_hex_color,
                  :other_message_hex_color,
                  :role_message_hex_colors,
                  :show_timestamp,
                  :show_role,
                  :active_chat_window,
                  :emit_typing_events,
                  :emit_message_events,
                  :emit_mention_events,
                  :show_self_signals,
                  :replace_signals_on_message_submit,
                  :message_css_class_resolver,
                  :render_message_html,
                  :message_html_tags,
                  :message_html_attributes,
                  :timestamp_formatter,
                  :role_formatter

    def initialize
      @permission_adapter = ChatGem::Permission
      @max_chat_participants = 10
      @max_message_length = 1000
      @message_history_limit = 200
      @enable_mentions = true
      @mention_filter_exclude_self = true
      @mention_filter_hide_roles = true
      @enable_emoji_aliases = true
      @emoji_aliases = DEFAULT_EMOJI_ALIASES.dup
      @blocked_words = []
      @blocked_words_action = DEFAULT_BLOCKED_WORDS_ACTION
      @blocked_words_scramble_chars = DEFAULT_BLOCKED_WORDS_SCRAMBLE_CHARS.dup
      @mention_mark_hex_color = nil
      @mention_highlight_hex_color = nil
      @own_message_hex_color = nil
      @other_message_hex_color = nil
      @role_message_hex_colors = {}
      @show_timestamp = true
      @show_role = false
      @active_chat_window = 5.minutes
      @emit_typing_events = false
      @emit_message_events = false
      @emit_mention_events = false
      @show_self_signals = false
      @replace_signals_on_message_submit = false
      @message_css_class_resolver = nil
      @render_message_html = false
      @message_html_tags = DEFAULT_MESSAGE_HTML_TAGS.dup
      @message_html_attributes = DEFAULT_MESSAGE_HTML_ATTRIBUTES.dup
      @additional_roles = {}
      @timestamp_formatter = lambda { |timestamp, _chat_message = nil|
        I18n.l(timestamp.in_time_zone, format: :long)
      }
      @role_formatter = lambda { |role, _chat_message = nil|
        role.to_s.humanize
      }
    end

    def add_role(key, name:, permissions:, rank: 0)
      normalized_key = normalize_role_key(key)
      raise ArgumentError, "Role key cannot be blank" if normalized_key.blank?
      raise ArgumentError, "Role #{normalized_key} is reserved" if DEFAULT_ROLE_DEFINITIONS.key?(normalized_key)

      role_name = name.to_s.strip
      raise ArgumentError, "Role name cannot be blank" if role_name.blank?

      @additional_roles[normalized_key] = {
        name: role_name,
        rank: rank.to_i,
        permissions: Array(permissions).map { |permission| permission.to_sym }.uniq
      }
    end

    def remove_role(key)
      @additional_roles.delete(normalize_role_key(key))
    end

    def clear_additional_roles!
      @additional_roles = {}
    end

    def additional_roles
      @additional_roles.dup
    end

    def role_definitions
      DEFAULT_ROLE_DEFINITIONS.merge(@additional_roles)
    end

    def role_definition(key)
      role_definitions[normalize_role_key(key)]
    end

    def add_emoji_alias(name, value)
      key = normalize_emoji_alias_key(name)
      raise ArgumentError, "Emoji alias cannot be blank" if key.blank?

      normalized_value = value.to_s.strip
      raise ArgumentError, "Emoji alias value cannot be blank" if normalized_value.blank?

      @emoji_aliases = effective_emoji_aliases.merge(key => normalized_value)
    end

    def remove_emoji_alias(name)
      key = normalize_emoji_alias_key(name)
      return if key.blank?

      @emoji_aliases = effective_emoji_aliases.except(key)
    end

    def clear_emoji_aliases!
      @emoji_aliases = {}
    end

    def reset_emoji_aliases!
      @emoji_aliases = DEFAULT_EMOJI_ALIASES.dup
    end

    def effective_emoji_aliases
      source = emoji_aliases.is_a?(Hash) ? emoji_aliases : {}

      source.each_with_object({}) do |(key, value), aliases|
        normalized_key = normalize_emoji_alias_key(key)
        normalized_value = value.to_s.strip
        next if normalized_key.blank? || normalized_value.blank?

        aliases[normalized_key] = normalized_value
      end
    end

    def effective_blocked_words
      source = blocked_words
      return [] unless source.respond_to?(:each)

      source.each_with_object([]) do |value, words|
        normalized_word = normalize_blocked_word(value)
        next if normalized_word.blank?
        next if words.include?(normalized_word)

        words << normalized_word
      end
    end

    def effective_blocked_words_action
      action = blocked_words_action.to_s.strip.downcase
      return DEFAULT_BLOCKED_WORDS_ACTION if action.blank?

      %w[reject scramble].include?(action) ? action : DEFAULT_BLOCKED_WORDS_ACTION
    end

    def effective_blocked_words_scramble_chars
      source = blocked_words_scramble_chars
      return DEFAULT_BLOCKED_WORDS_SCRAMBLE_CHARS.dup unless source.respond_to?(:each)

      chars = source.each_with_object([]) do |value, result|
        normalized_char = value.to_s
        next if normalized_char.blank?

        result << normalized_char
      end

      chars.presence || DEFAULT_BLOCKED_WORDS_SCRAMBLE_CHARS.dup
    end

    private

    def normalize_role_key(key)
      key.to_s.strip
    end

    def normalize_emoji_alias_key(key)
      key.to_s.strip.downcase
    end

    def normalize_blocked_word(word)
      word.to_s.strip.downcase
    end
  end
end
