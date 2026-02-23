module TurboChat
  module ApplicationHelper
    module ConfigSupport
      def chat_mention_filter_exclude_self?
        chat_config_boolean(:mention_filter_exclude_self, default: true)
      end

      def chat_mention_filter_hide_roles?
        chat_config_boolean(:mention_filter_hide_roles, default: true)
      end

      def chat_emit_mention_events?
        chat_config_boolean(:emit_mention_events, default: false)
      end

      def chat_emit_invitation_events?
        chat_config_boolean(:emit_invitation_events, default: false)
      end

      def chat_emit_chat_lifecycle_events?
        chat_config_boolean(:emit_chat_lifecycle_events, default: false)
      end

      def chat_show_members?
        chat_config_boolean(:show_members, default: true)
      end

      def chat_composer_placeholder_text
        value = chat_config_value(:composer_placeholder_text, default: "start chatting")
        normalized = value.to_s.strip
        normalized.present? ? normalized : "start chatting"
      end

      def chat_composer_add_files_display?
        chat_config_boolean(:composer_add_files_display, default: false)
      end

      def chat_composer_add_files_active?
        chat_config_boolean(:composer_add_files_active, default: false)
      end

      def chat_composer_microphone_display?
        chat_config_boolean(:composer_microphone_display, default: false)
      end

      def chat_composer_microphone_active?
        chat_config_boolean(:composer_microphone_active, default: false)
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

      private

      def chat_config_value(method_name, default: nil)
        configuration = TurboChat.configuration
        return default unless configuration.respond_to?(method_name)

        configuration.public_send(method_name)
      rescue StandardError
        default
      end

      def chat_config_boolean(method_name, default:)
        value = chat_config_value(method_name, default: default)
        ActiveModel::Type::Boolean.new.cast(value)
      end

      def normalize_config_source_key(value)
        value.to_s.strip.downcase.presence
      end
    end
  end
end
