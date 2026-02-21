module TurboChat
  class ChatMessage
    module Signals
      extend ActiveSupport::Concern

      class_methods do
        def start_signal!(chat:, participant:, signal_type: :typing)
          create!(chat: chat, participant: participant, kind: :signal, signal_type: signal_type)
        end

        def replace_signal!(chat:, participant:, signal_type: :typing)
          clear_signals!(chat: chat, participant: participant)
          start_signal!(chat: chat, participant: participant, signal_type: signal_type)
        end

        def clear_signals!(chat:, participant:)
          where(chat: chat, participant: participant, kind: kinds[:signal]).delete_all
          broadcast_signal_refresh(chat)
          true
        end

        def with_signal(chat:, participant:, signal_type: :typing)
          replace_signal!(chat: chat, participant: participant, signal_type: signal_type)
          yield
        ensure
          clear_signals!(chat: chat, participant: participant)
        end

        def broadcast_signal_refresh(chat)
          return unless defined?(Turbo::StreamsChannel)

          Turbo::StreamsChannel.broadcast_update_to(
            [chat, STREAM_NAME],
            target: ActionView::RecordIdentifier.dom_id(chat, :signals),
            partial: SIGNALS_PARTIAL,
            locals: { chat: chat }
          )
        end
      end

      private

      def normalize_signal_fields
        self.signal_type = nil if message? || system?
        self.body = "" if signal?
      end

      def replace_participant_signals_on_submit
        return unless TurboChat.configuration.replace_signals_on_message_submit
        return if chat_id.blank? || participant_type.blank? || participant_id.blank?

        self.class.where(
          chat_id: chat_id,
          participant_type: participant_type,
          participant_id: participant_id,
          kind: self.class.kinds[:signal]
        ).delete_all
      end
    end
  end
end
