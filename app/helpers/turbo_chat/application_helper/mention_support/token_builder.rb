module TurboChat
  module ApplicationHelper
    module MentionSupport
      module TokenBuilder
        private

        def participant_mention_base_identifier(participant)
          TurboChat::ParticipantIdentity.mention_base_identifier(participant)
        end

        def fallback_mention_identifier(participant)
          participant_id = participant.respond_to?(:id) ? participant.id : nil
          return "member_#{participant_id}" if participant_id.present?

          "member"
        end

        def normalized_mention_identifier(value)
          slug = I18n.transliterate(value.to_s)
          slug = slug.downcase.gsub(/[^a-z0-9_]+/, "_").gsub(/\A_+|_+\z/, "").squeeze("_")
          slug = "member_#{slug}" if slug.match?(/\A\d/)
          slug.presence
        end

        def unique_mention_token(identifier, taken_tokens)
          base = normalized_mention_identifier(identifier) || "member"
          token = "@#{base}"
          return taken_tokens[token] = token unless taken_tokens.key?(token)

          suffix = 2
          loop do
            candidate = "@#{base}_#{suffix}"
            unless taken_tokens.key?(candidate)
              taken_tokens[candidate] = candidate
              return candidate
            end
            suffix += 1
          end
        end
      end
    end
  end
end
