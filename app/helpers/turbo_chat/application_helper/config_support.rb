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
    end
  end
end
