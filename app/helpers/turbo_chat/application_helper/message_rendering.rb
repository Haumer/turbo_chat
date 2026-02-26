module TurboChat
  module ApplicationHelper
    module MessageRendering
      def chat_message_css_classes(chat_message:, own_message:)
        [
          "chat-bubble",
          (own_message ? "chat-bubble--own" : nil),
          *resolve_custom_message_css_classes(chat_message: chat_message, own_message: own_message)
        ].compact.uniq.join(" ")
      end

      def chat_message_inline_style(chat_message:, own_message:)
        hex_color = resolve_message_hex_color(chat_message: chat_message, own_message: own_message)
        return nil if hex_color.blank?

        "--chat-bubble-bg: #{hex_color}; --chat-bubble-border: #{hex_color};"
      end

      def chat_mentions_container_inline_style
        hex_color = normalize_hex_color(chat_config_value(:mention_mark_hex_color)) ||
                    normalize_hex_color(chat_config_value(:mention_highlight_hex_color))
        return nil if hex_color.blank?

        mention_mark_background = hex_color_with_alpha(hex_color, alpha: 0.22)
        "--chat-mention-highlight-color: #{hex_color}; --chat-mention-mark-background: #{mention_mark_background};"
      end

      def render_chat_message_body(chat_message)
        body = chat_message.body.to_s
        return content_tag(:p, decorate_plain_message_text(body).html_safe, class: "chat-body") unless TurboChat.configuration.render_message_html

        sanitized_html = sanitize(
          body,
          tags: Array(TurboChat.configuration.message_html_tags),
          attributes: Array(TurboChat.configuration.message_html_attributes)
        )
        content_tag(:div, sanitized_html, class: "chat-body")
      end

      def chat_message_mention_tokens(chat_message)
        return [] unless TurboChat.configuration.enable_mentions && chat_message.present?

        chat_message.body.to_s.scan(MENTION_PATTERN).uniq
      end

      private

      def resolve_custom_message_css_classes(chat_message:, own_message:)
        resolver = TurboChat.configuration.message_css_class_resolver
        return [] unless resolver.respond_to?(:call)

        classes = call_message_css_class_resolver(resolver, chat_message: chat_message, own_message: own_message)
        Array(classes).flat_map { |value| value.to_s.split(/\s+/) }.reject(&:blank?)
      rescue ArgumentError
        []
      end

      def resolve_message_hex_color(chat_message:, own_message:)
        role_color = resolve_role_message_hex_color(chat_message: chat_message, own_message: own_message)
        return role_color if role_color.present?

        base_color = own_message ? TurboChat.configuration.own_message_hex_color : TurboChat.configuration.other_message_hex_color
        normalize_hex_color(base_color)
      end

      def resolve_role_message_hex_color(chat_message:, own_message:)
        role_colors = TurboChat.configuration.role_message_hex_colors
        return nil unless role_colors.is_a?(Hash)

        role_key = chat_message_role_key(chat_message)
        return nil if role_key.blank?

        role_config = role_colors[role_key] || role_colors[role_key.to_sym]
        return normalize_hex_color(role_config) unless role_config.is_a?(Hash)

        normalize_hex_color(role_variant_color(role_config, own_message: own_message))
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

        red, green, blue = hex_rgb_components(normalized_hex)
        return nil if red.nil?

        alpha_hex = (alpha.to_f.clamp(0.0, 1.0) * 255).round.to_s(16).rjust(2, "0")
        "##{red}#{green}#{blue}#{alpha_hex}".downcase
      end

      def decorate_plain_message_text(body)
        formatted = ERB::Util.html_escape(body.to_s)
        formatted = apply_emoji_aliases(formatted) if TurboChat.configuration.enable_emoji_aliases
        formatted = apply_mention_highlights(formatted) if TurboChat.configuration.enable_mentions
        formatted.gsub(/\r\n?|\n/, "<br>")
      end

      def apply_emoji_aliases(text)
        emoji_aliases = TurboChat.configuration.effective_emoji_aliases
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

      def call_message_css_class_resolver(resolver, chat_message:, own_message:)
        case resolver.arity
        when 0 then resolver.call
        when 1 then resolver.call(chat_message)
        when 2 then resolver.call(chat_message, own_message)
        else resolver.call(chat_message, own_message, self)
        end
      end

      def role_variant_color(role_config, own_message:)
        variant_key = own_message ? "own" : "other"
        role_config[variant_key.to_sym] || role_config[variant_key] || role_config[:default] || role_config["default"]
      end

      def hex_rgb_components(normalized_hex)
        case normalized_hex.length
        when 4
          normalized_hex[1, 3].chars.map { |char| char * 2 }
        when 7, 9
          [normalized_hex[1, 2], normalized_hex[3, 2], normalized_hex[5, 2]]
        end
      end
    end
  end
end
