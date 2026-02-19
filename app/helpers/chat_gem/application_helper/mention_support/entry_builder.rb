module ChatGem
  module ApplicationHelper
    module MentionSupport
      module EntryBuilder
        private

        def chat_member_mention_entries(chat)
          taken_tokens = {}

          active_chat_memberships(chat).each_with_object([]) do |membership, entries|
            participant = membership.participant
            next if participant.nil?

            identifier = normalized_mention_identifier(participant_mention_base_identifier(participant))
            identifier = fallback_mention_identifier(participant) if identifier.blank?
            token = unique_mention_token(identifier, taken_tokens)

            entries << {
              token: token,
              label: chat_participant_name(participant),
              participant: participant,
              participant_type: participant.class.base_class.name,
              participant_id: participant.id
            }
          end
        end

        def chat_role_mention_entries(chat)
          role_tokens = {}

          active_chat_memberships(chat).each_with_object([]) do |membership, entries|
            role_key = membership.effective_role_key.to_s.strip
            next if role_key.blank?

            role_token = "@#{role_key.upcase}"
            next if role_tokens[role_token]

            role_tokens[role_token] = true
            entries << {
              token: role_token,
              label: "#{membership.effective_role_name} role",
              kind: "role"
            }
          end
        end

        def active_chat_memberships(chat)
          return [] unless chat.respond_to?(:chat_memberships)

          chat.chat_memberships.active.includes(:participant).order(:id)
        end
      end
    end
  end
end
