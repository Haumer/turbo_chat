module TurboChat
  class ChatMessage
    module Broadcasting
      extend ActiveSupport::Concern

      private

      def broadcast_create
        return unless respond_to?(:broadcast_update_to)

        stream = stream_name

        if appendable_timeline_message?
          broadcast_timeline_create(stream)
        end

        broadcast_update_to(
          stream,
          target: ActionView::RecordIdentifier.dom_id(chat, :signals),
          partial: SIGNALS_PARTIAL,
          locals: { chat: chat }
        )
      end

      def broadcast_update
        return unless message?
        return unless saved_change_to_body?
        return unless respond_to?(:broadcast_replace_to)

        broadcast_replace_to(
          stream_name,
          target: ActionView::RecordIdentifier.dom_id(self),
          partial: MESSAGE_PARTIAL,
          locals: { chat_message: self }
        )
      end

      def broadcast_destroy
        stream = stream_name

        if appendable_timeline_message? && respond_to?(:broadcast_remove_to)
          broadcast_remove_to(
            stream,
            target: ActionView::RecordIdentifier.dom_id(self)
          )
        end

        self.class.broadcast_signal_refresh(chat)
      end

      def stream_name
        [chat, STREAM_NAME]
      end

      def appendable_timeline_message?
        message? || system?
      end

      def broadcast_timeline_create(stream)
        options = {
          target: ActionView::RecordIdentifier.dom_id(chat, :messages),
          partial: CHAT_MESSAGE_PARTIAL,
          locals: { chat_message: self }
        }

        if append_start_position?
          return unless respond_to?(:broadcast_prepend_to)

          broadcast_prepend_to(stream, **options)
          return
        end

        return unless respond_to?(:broadcast_append_to)

        broadcast_append_to(stream, **options)
      end

      def append_start_position?
        configuration = TurboChat.configuration
        value = configuration.respond_to?(:message_insert_position) ? configuration.message_insert_position : "append_end"
        normalized = value.to_s.strip.downcase
        %w[append_start start prepend].include?(normalized)
      rescue StandardError
        false
      end
    end
  end
end
