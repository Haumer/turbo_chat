module ChatGem
  module ApplicationHelper
    HEX_COLOR_PATTERN = /\A#(?:\h{3}|\h{6}|\h{8})\z/.freeze
    EMOJI_ALIAS_PATTERN = /:([a-z0-9_+\-]{2,32}):/i.freeze
    MENTION_PATTERN = /(?<![[:alnum:]_])@[[:alpha:]][[:alnum:]_]{0,31}/.freeze

    def chat_message_css_classes(chat_message:, own_message:)
      classes = ["chat-bubble"]
      classes << "chat-bubble--own" if own_message
      classes.concat(resolve_custom_message_css_classes(chat_message: chat_message, own_message: own_message))
      classes.uniq.join(" ")
    end

    def chat_message_inline_style(chat_message:, own_message:)
      hex_color = resolve_message_hex_color(chat_message: chat_message, own_message: own_message)
      return nil if hex_color.blank?

      "--chat-bubble-bg: #{hex_color}; --chat-bubble-border: #{hex_color};"
    end

    def render_chat_message_body(chat_message)
      body = chat_message.body.to_s
      return content_tag(:p, decorate_plain_message_text(body).html_safe, class: "chat-body") unless ChatGem.configuration.render_message_html

      sanitized_html = sanitize(
        body,
        tags: Array(ChatGem.configuration.message_html_tags),
        attributes: Array(ChatGem.configuration.message_html_attributes)
      )
      content_tag(:div, sanitized_html, class: "chat-body")
    end

    def chat_participant_name(participant)
      return "Unknown" if participant.nil?
      return participant.name if participant.respond_to?(:name)
      return participant.email if participant.respond_to?(:email)

      participant.to_s
    end

    def chat_mention_options(chat:, permission: nil)
      mention_permission = permission || mention_permission_for(chat)
      allow_member_mentions = mention_permission.nil? ? true : mention_permission_allows?(mention_permission, :can_mention_members?)
      allow_all_mentions = mention_permission.nil? ? true : mention_permission_allows?(mention_permission, :can_mention_all?)
      allow_role_mentions = mention_permission.nil? ? true : mention_permission_allows?(mention_permission, :can_mention_roles?)

      options = []
      options << { token: "@all", label: "All members", kind: "group" } if allow_all_mentions
      return options unless chat.respond_to?(:chat_memberships)

      memberships = chat.chat_memberships.active.includes(:participant)
      taken_tokens = {}
      role_tokens = {}

      if allow_member_mentions
        memberships.each do |membership|
          participant = membership.participant
          next if participant.nil?

          identifier = normalized_mention_identifier(participant_mention_base_identifier(participant))
          identifier = fallback_mention_identifier(participant) if identifier.blank?
          token = unique_mention_token(identifier, taken_tokens)
          options << {
            token: token,
            label: chat_participant_name(participant),
            kind: "member"
          }
        end
      end

      if allow_role_mentions
        memberships.each do |membership|
          role_key = membership.effective_role_key.to_s.strip
          next if role_key.blank?

          role_token = "@#{role_key.upcase}"
          next if role_tokens[role_token]

          role_tokens[role_token] = true
          options << {
            token: role_token,
            label: "#{membership.effective_role_name} role",
            kind: "role"
          }
        end
      end

      options
    end

    def chat_mentions_enabled_for?(chat:, permission: nil)
      return false unless ChatGem.configuration.enable_mentions

      mention_permission = permission || mention_permission_for(chat)
      return true if mention_permission.nil?

      mention_permission_allows?(mention_permission, :can_mention_members?) ||
        mention_permission_allows?(mention_permission, :can_mention_all?) ||
        mention_permission_allows?(mention_permission, :can_mention_roles?)
    end

    private

    def resolve_custom_message_css_classes(chat_message:, own_message:)
      resolver = ChatGem.configuration.message_css_class_resolver
      return [] unless resolver.respond_to?(:call)

      classes = case resolver.arity
      when 0
        resolver.call
      when 1
        resolver.call(chat_message)
      when 2
        resolver.call(chat_message, own_message)
      else
        resolver.call(chat_message, own_message, self)
      end

      Array(classes).flat_map { |value| value.to_s.split(/\s+/) }.reject(&:blank?)
    rescue ArgumentError
      []
    end

    def resolve_message_hex_color(chat_message:, own_message:)
      role_color = resolve_role_message_hex_color(chat_message: chat_message, own_message: own_message)
      return role_color if role_color.present?

      base_color = own_message ? ChatGem.configuration.own_message_hex_color : ChatGem.configuration.other_message_hex_color
      normalize_hex_color(base_color)
    end

    def resolve_role_message_hex_color(chat_message:, own_message:)
      role_colors = ChatGem.configuration.role_message_hex_colors
      return nil unless role_colors.is_a?(Hash)

      role_key = chat_message_role_key(chat_message)
      return nil if role_key.blank?

      role_config = role_colors[role_key] || role_colors[role_key.to_sym]
      return normalize_hex_color(role_config) unless role_config.is_a?(Hash)

      variant = if own_message
                  role_config[:own] || role_config["own"]
                else
                  role_config[:other] || role_config["other"]
                end

      variant ||= role_config[:default] || role_config["default"]
      normalize_hex_color(variant)
    end

    def chat_message_role_key(chat_message)
      return nil unless chat_message.respond_to?(:participant_membership_role)

      chat_message.participant_membership_role.to_s.strip.presence
    end

    def normalize_hex_color(value)
      candidate = value.to_s.strip
      return nil if candidate.blank?

      candidate = "##{candidate}" unless candidate.start_with?("#")
      return nil unless HEX_COLOR_PATTERN.match?(candidate)

      candidate.downcase
    end

    def decorate_plain_message_text(body)
      formatted = ERB::Util.html_escape(body.to_s)
      formatted = apply_emoji_aliases(formatted) if ChatGem.configuration.enable_emoji_aliases
      formatted = apply_mention_highlights(formatted) if ChatGem.configuration.enable_mentions
      formatted.gsub(/\r\n?|\n/, "<br>")
    end

    def apply_emoji_aliases(text)
      emoji_aliases = ChatGem.configuration.effective_emoji_aliases
      return text if emoji_aliases.empty?

      text.gsub(EMOJI_ALIAS_PATTERN) do |match|
        alias_key = Regexp.last_match(1).to_s.downcase
        emoji_aliases.fetch(alias_key, match)
      end
    end

    def apply_mention_highlights(text)
      text.gsub(MENTION_PATTERN) do |mention|
        %(<span class="chat-mention">#{mention}</span>)
      end
    end

    def participant_mention_base_identifier(participant)
      return participant.username if participant.respond_to?(:username) && participant.username.present?
      if participant.respond_to?(:email) && participant.email.present?
        return participant.email.to_s.split("@").first
      end
      return participant.name if participant.respond_to?(:name) && participant.name.present?

      participant.to_s
    end

    def fallback_mention_identifier(participant)
      participant_id = participant.respond_to?(:id) ? participant.id : nil
      return "member_#{participant_id}" if participant_id.present?

      "member"
    end

    def normalized_mention_identifier(value)
      slug = I18n.transliterate(value.to_s)
      slug = slug.downcase.gsub(/[^a-z0-9_]+/, "_").gsub(/\A_+|_+\z/, "").squeeze("_")
      slug = "member_#{slug}" if slug.match?(/\A\d/)
      slug.presence
    end

    def unique_mention_token(identifier, taken_tokens)
      base = normalized_mention_identifier(identifier) || "member"
      token = "@#{base}"
      return taken_tokens[token] = token unless taken_tokens.key?(token)

      suffix = 2
      loop do
        candidate = "@#{base}_#{suffix}"
        unless taken_tokens.key?(candidate)
          taken_tokens[candidate] = candidate
          return candidate
        end
        suffix += 1
      end
    end

    def mention_permission_for(chat)
      return nil unless respond_to?(:current_chat_participant, true)

      participant = current_chat_participant
      return nil if participant.nil?

      ChatGem.configuration.permission_adapter.new(participant, chat)
    rescue StandardError
      nil
    end

    def mention_permission_allows?(permission, method_name)
      return true unless permission.respond_to?(method_name)

      permission.public_send(method_name)
    rescue StandardError
      false
    end
  end
end
