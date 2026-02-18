module ChatGem
  module ApplicationHelper
    HEX_COLOR_PATTERN = /\A#(?:\h{3}|\h{6}|\h{8})\z/.freeze

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
      return content_tag(:p, body, class: "chat-body") unless ChatGem.configuration.render_message_html

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
  end
end
