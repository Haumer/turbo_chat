module ChatGem
  module ApplicationHelper
    module MessageRendering
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

      def chat_mentions_container_inline_style
        hex_color = normalize_hex_color(chat_config_value(:mention_mark_hex_color))
        hex_color ||= normalize_hex_color(chat_config_value(:mention_highlight_hex_color))
        return nil if hex_color.blank?

        mention_mark_background = hex_color_with_alpha(hex_color, alpha: 0.22)
        "--chat-mention-highlight-color: #{hex_color}; --chat-mention-mark-background: #{mention_mark_background};"
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

      def chat_message_mention_tokens(chat_message)
        return [] unless ChatGem.configuration.enable_mentions
        return [] if chat_message.nil?

        chat_message.body.to_s.scan(MENTION_PATTERN).uniq
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

      def hex_color_with_alpha(hex_color, alpha:)
        normalized_hex = normalize_hex_color(hex_color)
        return nil if normalized_hex.blank?

        red, green, blue = case normalized_hex.length
                           when 4
                             [
                               normalized_hex[1] * 2,
                               normalized_hex[2] * 2,
                               normalized_hex[3] * 2
                             ]
                           when 7, 9
                             [
                               normalized_hex[1, 2],
                               normalized_hex[3, 2],
                               normalized_hex[5, 2]
                             ]
                           else
                             return nil
                           end

        alpha_value = alpha.to_f
        alpha_value = 0.0 if alpha_value.negative?
        alpha_value = 1.0 if alpha_value > 1.0

        alpha_hex = (alpha_value * 255).round.to_s(16).rjust(2, "0")
        "##{red}#{green}#{blue}#{alpha_hex}".downcase
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
    end
  end
end
