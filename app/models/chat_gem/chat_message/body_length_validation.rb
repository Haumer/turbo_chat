module ChatGem
  class ChatMessage
    module BodyLengthValidation
      extend ActiveSupport::Concern

      private

      def body_within_max_length
        configured_limit = ChatGem.configuration.max_message_length
        return if configured_limit.nil?

        limit = configured_limit.to_i
        return if limit <= 0
        return if body.to_s.length <= limit

        errors.add(:body, "is too long (maximum is #{limit} characters)")
      end
    end
  end
end
