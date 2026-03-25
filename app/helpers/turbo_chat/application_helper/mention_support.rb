module TurboChat
  module ApplicationHelper
    module MentionSupport
      include TurboChat::ApplicationHelper::MentionSupport::TokenBuilder
      include TurboChat::ApplicationHelper::MentionSupport::EntryBuilder
      include TurboChat::ApplicationHelper::MentionSupport::PermissionSupport

      def chat_mention_options(chat:, permission: nil)
        mention_permission = permission || mention_permission_for(chat)
        allow_member_mentions = mention_permission.nil? ? true : mention_permission_allows?(mention_permission, :can_mention_members?)
        allow_all_mentions = mention_permission.nil? ? true : mention_permission_allows?(mention_permission, :can_mention_all?)
        allow_role_mentions = mention_permission.nil? ? true : mention_permission_allows?(mention_permission, :can_mention_roles?)
        allow_role_mentions &&= !chat_mention_filter_hide_roles?(chat: chat)
        exclude_self_mentions = chat_mention_filter_exclude_self?(chat: chat)
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

      def chat_member_mention_lookup(chat:)
        chat_member_mention_entries(chat).each_with_object({}) do |entry, lookup|
          key = "#{entry[:participant_type]}:#{entry[:participant_id]}"
          lookup[key] = entry
        end
      end

      def chat_mentions_enabled_for?(chat:, permission: nil)
        return false unless chat_enable_mentions?(chat: chat)

        mention_permission = permission || mention_permission_for(chat)
        return true if mention_permission.nil?

        mention_permission_allows?(mention_permission, :can_mention_members?) ||
          mention_permission_allows?(mention_permission, :can_mention_all?) ||
          mention_permission_allows?(mention_permission, :can_mention_roles?)
      end
    end
  end
end
