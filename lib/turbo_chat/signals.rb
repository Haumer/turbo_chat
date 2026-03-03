module TurboChat
  module Signals
    module_function

    def start!(chat:, participant:, signal_type: :typing, signal_text: nil)
      TurboChat::ChatMessage.start_signal!(
        chat: chat,
        participant: participant,
        signal_type: signal_type,
        signal_text: signal_text
      )
    end

    def replace!(chat:, participant:, signal_type: :typing, signal_text: nil)
      TurboChat::ChatMessage.replace_signal!(
        chat: chat,
        participant: participant,
        signal_type: signal_type,
        signal_text: signal_text
      )
    end

    def clear!(chat:, participant:)
      TurboChat::ChatMessage.clear_signals!(chat: chat, participant: participant)
    end

    def custom!(chat:, participant:, signal_text:)
      start!(chat: chat, participant: participant, signal_type: :custom, signal_text: signal_text)
    end

    def with(chat:, participant:, signal_type: :typing, signal_text: nil, &block)
      TurboChat::ChatMessage.with_signal(
        chat: chat,
        participant: participant,
        signal_type: signal_type,
        signal_text: signal_text,
        &block
      )
    end
  end
end
