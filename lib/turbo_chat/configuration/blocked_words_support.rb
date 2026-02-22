class TurboChat::Configuration
  module BlockedWordsSupport
    def effective_blocked_words
      source = blocked_words
      return [] unless source.respond_to?(:each)

      source.each_with_object([]) do |value, words|
        normalized_word = normalize_blocked_word(value)
        next if normalized_word.blank?
        next if words.include?(normalized_word)

        words << normalized_word
      end
    end

    def effective_blocked_words_action
      action = blocked_words_action.to_s.strip.downcase
      return DEFAULT_BLOCKED_WORDS_ACTION if action.blank?

      %w[reject scramble].include?(action) ? action : DEFAULT_BLOCKED_WORDS_ACTION
    end

    def effective_blocked_words_scramble_chars
      source = blocked_words_scramble_chars
      return DEFAULT_BLOCKED_WORDS_SCRAMBLE_CHARS.dup unless source.respond_to?(:each)

      chars = source.each_with_object([]) do |value, result|
        normalized_char = value.to_s
        next if normalized_char.blank?

        result << normalized_char
      end

      chars.presence || DEFAULT_BLOCKED_WORDS_SCRAMBLE_CHARS.dup
    end

    private

    def normalize_blocked_word(word) = word.to_s.strip.downcase
  end
end
