class TurboChat::Configuration
  module EmojiSupport
    def add_emoji_alias(name, value)
      key = normalize_emoji_alias_key(name)
      raise ArgumentError, "Emoji alias cannot be blank" if key.blank?

      normalized_value = value.to_s.strip
      raise ArgumentError, "Emoji alias value cannot be blank" if normalized_value.blank?

      @emoji_aliases = effective_emoji_aliases.merge(key => normalized_value)
    end

    def remove_emoji_alias(name)
      key = normalize_emoji_alias_key(name)
      return if key.blank?

      @emoji_aliases = effective_emoji_aliases.except(key)
    end

    def clear_emoji_aliases! = @emoji_aliases = {}

    def reset_emoji_aliases! = @emoji_aliases = DEFAULT_EMOJI_ALIASES.dup

    def effective_emoji_aliases
      source = emoji_aliases.is_a?(Hash) ? emoji_aliases : {}

      source.each_with_object({}) do |(key, value), aliases|
        normalized_key = normalize_emoji_alias_key(key)
        normalized_value = value.to_s.strip
        next if normalized_key.blank? || normalized_value.blank?

        aliases[normalized_key] = normalized_value
      end
    end

    private

    def normalize_emoji_alias_key(key) = key.to_s.strip.downcase
  end
end
