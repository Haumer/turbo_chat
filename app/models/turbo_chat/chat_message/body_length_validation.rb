module TurboChat
  class ChatMessage
    module BodyLengthValidation
      extend ActiveSupport::Concern

      private

      def body_within_max_length
        configured_limit = TurboChat::Configuration.config_value(:max_message_length, default: 1000, chat: chat)
        return if configured_limit.nil?

        limit = configured_limit.to_i
        return if limit <= 0
        return if body.to_s.length <= limit

        errors.add(:body, "is too long (maximum is #{limit} characters)")
      end
    end
  end
end
