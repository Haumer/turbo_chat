module ChatGem
  class ChatMessage
    module Broadcasting
      extend ActiveSupport::Concern

      private

      def broadcast_create
        return unless respond_to?(:broadcast_update_to)

        stream = stream_name

        if message? && respond_to?(:broadcast_append_to)
          broadcast_append_to(
            stream,
            target: ActionView::RecordIdentifier.dom_id(chat, :messages),
            partial: CHAT_MESSAGE_PARTIAL,
            locals: { chat_message: self }
          )
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

        if message? && respond_to?(:broadcast_remove_to)
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
    end
  end
end
