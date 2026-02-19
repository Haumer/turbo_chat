module TurboChat
  module Signals
    module_function

    def start!(chat:, participant:, signal_type: :typing)
      TurboChat::ChatMessage.replace_signal!(chat: chat, participant: participant, signal_type: signal_type)
    end

    def replace!(chat:, participant:, signal_type: :typing)
      TurboChat::ChatMessage.replace_signal!(chat: chat, participant: participant, signal_type: signal_type)
    end

    def clear!(chat:, participant:)
      TurboChat::ChatMessage.clear_signals!(chat: chat, participant: participant)
    end

    def with(chat:, participant:, signal_type: :typing, &block)
      TurboChat::ChatMessage.with_signal(
        chat: chat,
        participant: participant,
        signal_type: signal_type,
        &block
      )
    end
  end
end
