module TurboChat
  class ChatMessage
    module BlockedWordsModeration
      extend ActiveSupport::Concern

      private

      def apply_blocked_words_moderation
        blocked_words = blocked_words_from_configuration
        return if blocked_words.empty?

        matches = blocked_words_in_body(blocked_words)
        return if matches.empty?

        action = blocked_words_action_from_configuration
        emit_blocked_words_event(
          "turbo_chat.blocked_words.detected",
          blocked_words: matches,
          action: action
        )
        if action == "scramble"
          original_body = body.to_s.dup
          scramble_blocked_words!(blocked_words)
          emit_blocked_words_event(
            "turbo_chat.blocked_words.scrambled",
            blocked_words: matches,
            action: action,
            original_body: original_body,
            moderated_body: body.to_s
          )
          return
        end

        errors.add(:body, "contains blocked language")
        emit_blocked_words_event(
          "turbo_chat.blocked_words.rejected",
          blocked_words: matches,
          action: action
        )
      end

      def blocked_words_in_body(blocked_words)
        blocked_words.select { |word| blocked_word_pattern(word).match?(body.to_s) }
      end

      def scramble_blocked_words!(blocked_words)
        moderated_body = body.to_s.dup

        blocked_words.each do |word|
          moderated_body.gsub!(blocked_word_pattern(word)) do |match|
            scramble_word(match)
          end
        end

        self.body = moderated_body
      end

      def scramble_word(word)
        source = word.to_s
        characters = source.chars
        return source if characters.length < 2

        scrambled = characters.shuffle
        if scrambled == characters && characters.uniq.length > 1
          scrambled = characters.rotate(1)
        end

        scrambled.join
      end

      def blocked_word_pattern(word)
        /(?<![[:alnum:]_])#{Regexp.escape(word)}(?![[:alnum:]_])/i
      end

      def blocked_words_from_configuration
        configuration = TurboChat.configuration
        return [] unless configuration.respond_to?(:effective_blocked_words)

        Array(configuration.effective_blocked_words)
      rescue StandardError
        []
      end

      def blocked_words_action_from_configuration
        configuration = TurboChat.configuration
        return "reject" unless configuration.respond_to?(:effective_blocked_words_action)

        configuration.effective_blocked_words_action.to_s
      rescue StandardError
        "reject"
      end

      def emit_blocked_words_event(name, blocked_words:, action:, original_body: nil, moderated_body: nil)
        return unless blocked_words_events_enabled?
        return unless defined?(ActiveSupport::Notifications)

        payload = {
          chat_id: chat_id,
          message_id: id,
          participant_type: participant_type,
          participant_id: participant_id,
          blocked_words: Array(blocked_words).map(&:to_s),
          action: action.to_s
        }
        payload[:original_body] = original_body if original_body.present?
        payload[:moderated_body] = moderated_body if moderated_body.present?
        ActiveSupport::Notifications.instrument(name, payload)
      end

      def blocked_words_events_enabled?
        configuration = TurboChat.configuration
        return false unless configuration.respond_to?(:emit_blocked_words_events)

        ActiveModel::Type::Boolean.new.cast(configuration.emit_blocked_words_events)
      rescue StandardError
        false
      end
    end
  end
end
