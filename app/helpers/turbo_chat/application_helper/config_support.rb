module TurboChat
  module ApplicationHelper
    module ConfigSupport
      BOOLEAN_CHAT_SETTINGS = {
        enable_mentions: true,
        mention_filter_exclude_self: true,
        mention_filter_hide_roles: true,
        emit_typing_events: false,
        emit_message_events: false,
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
        composer_microphone_active: false,
        signal_text_sheen: true,
        show_timestamp: true,
        show_role: false,
        render_message_html: false
      }.freeze

      BOOLEAN_CHAT_SETTINGS.each do |setting, default|
        define_method("chat_#{setting}?") do |chat: nil|
          chat_config_boolean(setting, default: default, chat: chat)
        end
      end

      def chat_composer_placeholder_text(chat: nil)
        value = chat_config_value(:composer_placeholder_text, default: "start chatting", chat: chat)
        normalized = value.to_s.strip
        normalized.present? ? normalized : "start chatting"
      end

      def chat_message_source_labels(chat: nil)
        configured = chat_config_value(:message_source_labels, default: {}, chat: chat)
        return {} unless configured.respond_to?(:each_pair)

        configured.each_with_object({}) do |(source_key, label), normalized|
          source = normalize_config_source_key(source_key)
          next if source.blank?

          rendered_label = label.to_s.strip
          next if rendered_label.blank?

          normalized[source] = rendered_label
        end
      end

      def chat_message_source_label(source, chat: nil)
        source_key = TurboChat::ChatMessage.normalize_source_key(source)
        labels = chat_message_source_labels(chat: chat)
        label = labels[source_key]
        return label if label.present?

        source_key.tr("_-", " ").split.map(&:capitalize).join(" ")
      end

      def chat_message_source_badge_label(chat_message)
        return nil unless chat_message.respond_to?(:source)

        source_key = TurboChat::ChatMessage.normalize_source_key(chat_message.source)
        return nil if source_key == TurboChat::ChatMessage::DEFAULT_SOURCE

        message_chat = chat_message.respond_to?(:chat) ? chat_message.chat : nil
        chat_message_source_label(source_key, chat: message_chat)
      end

      def chat_style_key(chat: nil)
        raw_style = chat_config_value(:chat_style, default: "chat_style_bounded", chat: chat)
        normalized = raw_style.to_s.strip.downcase

        case normalized
        when "chat_style_unbounded", "unbounded"
          "chat_style_unbounded"
        else
          "chat_style_bounded"
        end
      end

      def chat_unbounded_style?(chat: nil)
        chat_style_key(chat: chat) == "chat_style_unbounded"
      end

      def chat_shell_style_class(chat: nil)
        chat_unbounded_style?(chat: chat) ? "chat-shell--style-unbounded" : "chat-shell--style-bounded"
      end

      def chat_message_insert_position(chat: nil)
        raw_position = chat_config_value(:message_insert_position, default: "append_end", chat: chat)
        normalized = raw_position.to_s.strip.downcase

        case normalized
        when "append_start", "start", "prepend"
          "append_start"
        else
          "append_end"
        end
      end

      def chat_message_append_start?(chat: nil)
        chat_message_insert_position(chat: chat) == "append_start"
      end

      def chat_signal_ttl_seconds(chat: nil)
        value = chat_config_value(:signal_ttl_seconds, default: 60, chat: chat)
        ttl = value.to_i
        ttl.positive? ? ttl : 60
      end

      def chat_mode_key(chat)
        TurboChat::Configuration.extract_chat_mode(chat) || :standard
      end

      def chat_assistant_mode?(chat)
        chat_mode_key(chat) == :assistant
      end

      private

      def chat_config_value(method_name, default: nil, chat: nil)
        TurboChat::Configuration.config_value(method_name, default: default, chat: chat)
      end

      def chat_config_boolean(method_name, default:, chat: nil)
        TurboChat::Configuration.config_boolean(method_name, default: default, chat: chat)
      end

      def normalize_config_source_key(value)
        value.to_s.strip.downcase.presence
      end
    end
  end
end
