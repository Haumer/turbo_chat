module TurboChat
  module ApplicationHelper
    module ConfigSupport
      BOOLEAN_CHAT_SETTINGS = {
        mention_filter_exclude_self: true,
        mention_filter_hide_roles: true,
        emit_mention_events: false,
        emit_invitation_events: false,
        emit_chat_lifecycle_events: false,
        show_members: true,
        show_members_list: true,
        show_members_invite_controls: true,
        show_invite_fallback_when_members_hidden: true,
        show_self_signals: false,
        disable_input: false,
        show_header_title: true,
        show_header_status: true,
        show_header_close_action: true,
        show_header_leave_action: true,
        show_header_back_action: true,
        composer_add_files_display: false,
        composer_add_files_active: false,
        composer_microphone_display: false,
        composer_microphone_active: false
      }.freeze

      BOOLEAN_CHAT_SETTINGS.each do |setting, default|
        define_method("chat_#{setting}?") do
          chat_config_boolean(setting, default: default)
        end
      end

      def chat_composer_placeholder_text
        value = chat_config_value(:composer_placeholder_text, default: "start chatting")
        normalized = value.to_s.strip
        normalized.present? ? normalized : "start chatting"
      end

      def chat_message_source_labels
        configured = chat_config_value(:message_source_labels, default: {})
        return {} unless configured.respond_to?(:each_pair)

        configured.each_with_object({}) do |(source_key, label), normalized|
          source = normalize_config_source_key(source_key)
          next if source.blank?

          rendered_label = label.to_s.strip
          next if rendered_label.blank?

          normalized[source] = rendered_label
        end
      end

      def chat_message_source_label(source)
        source_key = TurboChat::ChatMessage.normalize_source_key(source)
        labels = chat_message_source_labels
        label = labels[source_key]
        return label if label.present?

        source_key.tr("_-", " ").split.map(&:capitalize).join(" ")
      end

      def chat_message_source_badge_label(chat_message)
        return nil unless chat_message.respond_to?(:source)

        source_key = TurboChat::ChatMessage.normalize_source_key(chat_message.source)
        return nil if source_key == TurboChat::ChatMessage::DEFAULT_SOURCE

        chat_message_source_label(source_key)
      end

      def chat_style_key
        raw_style = chat_config_value(:chat_style, default: "chat_style_bounded")
        normalized = raw_style.to_s.strip.downcase

        case normalized
        when "chat_style_unbounded", "unbounded"
          "chat_style_unbounded"
        else
          "chat_style_bounded"
        end
      end

      def chat_unbounded_style?
        chat_style_key == "chat_style_unbounded"
      end

      def chat_shell_style_class
        chat_unbounded_style? ? "chat-shell--style-unbounded" : "chat-shell--style-bounded"
      end

      def chat_message_insert_position
        raw_position = chat_config_value(:message_insert_position, default: "append_end")
        normalized = raw_position.to_s.strip.downcase

        case normalized
        when "append_start", "start", "prepend"
          "append_start"
        else
          "append_end"
        end
      end

      def chat_message_append_start?
        chat_message_insert_position == "append_start"
      end

      def chat_signal_ttl_seconds
        value = chat_config_value(:signal_ttl_seconds, default: 60)
        ttl = value.to_i
        ttl.positive? ? ttl : 60
      end

      private

      def chat_config_value(method_name, default: nil)
        configuration = TurboChat.configuration
        return default unless configuration.respond_to?(method_name)

        configuration.public_send(method_name)
      rescue NoMethodError, TypeError
        default
      end

      def chat_config_boolean(method_name, default:)
        TurboChat::Configuration.config_boolean(method_name, default: default)
      end

      def normalize_config_source_key(value)
        value.to_s.strip.downcase.presence
      end
    end
  end
end
