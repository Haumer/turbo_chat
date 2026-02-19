module ChatGem
  module ApplicationHelper
    module MentionSupport
      def chat_mention_options(chat:, permission: nil)
        mention_permission = permission || mention_permission_for(chat)
        allow_member_mentions = mention_permission.nil? ? true : mention_permission_allows?(mention_permission, :can_mention_members?)
        allow_all_mentions = mention_permission.nil? ? true : mention_permission_allows?(mention_permission, :can_mention_all?)
        allow_role_mentions = mention_permission.nil? ? true : mention_permission_allows?(mention_permission, :can_mention_roles?)
        allow_role_mentions &&= !chat_mention_filter_hide_roles?
        exclude_self_mentions = chat_mention_filter_exclude_self?
        viewer_participant = mention_viewer_participant(permission: mention_permission)

        options = []
        options << { token: "@all", label: "All members", kind: "group" } if allow_all_mentions
        return options unless chat.respond_to?(:chat_memberships)

        if allow_member_mentions
          chat_member_mention_entries(chat).each do |entry|
            next if exclude_self_mentions && same_chat_participant?(entry[:participant], viewer_participant)

            options << {
              token: entry[:token],
              label: entry[:label],
              kind: "member",
              participant_type: entry[:participant_type],
              participant_id: entry[:participant_id]
            }
          end
        end

        if allow_role_mentions
          options.concat(chat_role_mention_entries(chat))
        end

        options
      end

      def chat_self_mention_tokens(chat:, participant: nil)
        viewer = participant || current_chat_participant_for_view
        return [] if viewer.nil?
        return [] unless chat.respond_to?(:chat_memberships)

        chat_member_mention_entries(chat).each_with_object([]) do |entry, tokens|
          next unless same_chat_participant?(entry[:participant], viewer)

          tokens << entry[:token]
        end
      end

      def chat_self_role_mention_token(chat:, participant: nil)
        viewer = participant || current_chat_participant_for_view
        return nil if viewer.nil?
        return nil unless chat.respond_to?(:chat_memberships)

        membership = chat.chat_memberships.active.find_by(participant: viewer)
        return nil if membership.nil?

        role_key = membership.effective_role_key.to_s.strip
        return nil if role_key.blank?

        "@#{role_key.upcase}"
      end

      def chat_mentions_enabled_for?(chat:, permission: nil)
        return false unless ChatGem.configuration.enable_mentions

        mention_permission = permission || mention_permission_for(chat)
        return true if mention_permission.nil?

        mention_permission_allows?(mention_permission, :can_mention_members?) ||
          mention_permission_allows?(mention_permission, :can_mention_all?) ||
          mention_permission_allows?(mention_permission, :can_mention_roles?)
      end

      private

      def participant_mention_base_identifier(participant)
        return participant.username if participant.respond_to?(:username) && participant.username.present?
        if participant.respond_to?(:email) && participant.email.present?
          return participant.email.to_s.split("@").first
        end
        return participant.name if participant.respond_to?(:name) && participant.name.present?

        participant.to_s
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

      def mention_permission_for(chat)
        return nil unless respond_to?(:current_chat_participant, true)

        participant = current_chat_participant
        return nil if participant.nil?

        ChatGem.configuration.permission_adapter.new(participant, chat)
      rescue StandardError
        nil
      end

      def mention_permission_allows?(permission, method_name)
        return true unless permission.respond_to?(method_name)

        permission.public_send(method_name)
      rescue StandardError
        false
      end
    end
  end
end
