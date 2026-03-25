module TurboChat
  class ChatMessage
    module Signals
      extend ActiveSupport::Concern

      class_methods do
        def start_signal!(chat:, participant:, signal_type: :typing, signal_text: nil)
          create!(
            chat: chat,
            participant: participant,
            kind: :signal,
            signal_type: signal_type,
            body: signal_text
          )
        end

        def replace_signal!(chat:, participant:, signal_type: :typing, signal_text: nil)
          transaction do
            clear_signals!(chat: chat, participant: participant, broadcast: false)
            start_signal!(chat: chat, participant: participant, signal_type: signal_type, signal_text: signal_text)
          end
        end

        def clear_signals!(chat:, participant:, broadcast: true)
          where(chat: chat, participant: participant, kind: kinds[:signal]).delete_all
          broadcast_signal_refresh(chat) if broadcast
          true
        end

        def with_signal(chat:, participant:, signal_type: :typing, signal_text: nil)
          replace_signal!(
            chat: chat,
            participant: participant,
            signal_type: signal_type,
            signal_text: signal_text
          )
          yield
        ensure
          clear_signals!(chat: chat, participant: participant)
        end

        def broadcast_signal_refresh(chat)
          return unless defined?(Turbo::StreamsChannel)

          Turbo::StreamsChannel.broadcast_update_to(
            [chat, STREAM_NAME],
            attributes: { method: :morph },
            target: ActionView::RecordIdentifier.dom_id(chat, :signals),
            partial: SIGNALS_PARTIAL,
            locals: { chat: chat }
          )
        end
      end

      private

      def normalize_signal_fields
        self.signal_type = nil if message? || system?
        return unless signal?

        self.body = signal_type_custom? ? body.to_s.strip : ""
      end

      def replace_participant_signals_on_submit
        return unless TurboChat::Configuration.config_boolean(:replace_signals_on_message_submit, default: false, chat: chat)
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
