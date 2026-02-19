module ChatGem
  class ChatMessage
    module MentionValidation
      extend ActiveSupport::Concern

      private

      def mentions_allowed_for_participant
        return unless ChatGem.configuration.enable_mentions

        mentions = mention_tokens
        return if mentions.empty?

        permission = mention_permission
        if permission.nil?
          errors.add(:body, "mentions cannot be validated at this time")
          return
        end

        invalid_mention = first_invalid_mention(permission, mentions)
        return if invalid_mention.nil?

        errors.add(:body, mention_permission_error(invalid_mention))
      end

      def mention_tokens
        body.to_s.scan(MENTION_PATTERN).uniq
      end

      def first_invalid_mention(permission, mentions)
        mentions.find { |mention| !mention_allowed?(permission, mention) }
      end

      def mention_permission
        adapter = ChatGem.configuration.permission_adapter
        return nil unless adapter.respond_to?(:new)

        adapter.new(participant, chat)
      rescue StandardError
        nil
      end

      def mention_allowed?(permission, mention)
        if permission.respond_to?(:can_mention_token?)
          return permission.can_mention_token?(mention)
        end

        case mention_kind(mention)
        when :all
          permission_gate_allowed?(permission, :can_mention_all?)
        when :role
          permission_gate_allowed?(permission, :can_mention_roles?)
        else
          permission_gate_allowed?(permission, :can_mention_members?)
        end
      rescue StandardError
        false
      end

      def permission_gate_allowed?(permission, method_name)
        return true unless permission.respond_to?(method_name)

        permission.public_send(method_name)
      end

      def mention_kind(mention)
        return :all if mention.casecmp("@all").zero?
        return :role if ROLE_MENTION_PATTERN.match?(mention)

        :member
      end

      def mention_permission_error(mention)
        case mention_kind(mention)
        when :all
          "cannot mention @all"
        when :role
          "cannot mention roles"
        else
          "cannot mention other members"
        end
      end
    end
  end
end
