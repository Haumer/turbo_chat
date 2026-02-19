module ChatGem
  class ChatMessage
    module Formatting
      extend ActiveSupport::Concern

      def participant_display_name
        return "Unknown" if participant.nil?
        return participant.username if participant.respond_to?(:username) && participant.username.present?
        return participant.name if participant.respond_to?(:name) && participant.name.present?
        return participant.email if participant.respond_to?(:email) && participant.email.present?

        participant.to_s
      end

      def formatted_timestamp
        formatted_time_for(created_at)
      end

      def formatted_updated_timestamp
        formatted_time_for(updated_at)
      end

      def edited?
        return false if created_at.blank? || updated_at.blank?

        updated_at > created_at
      end

      def participant_membership_role
        membership = participant_membership
        return nil if membership.nil?

        membership.effective_role_key
      end

      def formatted_participant_role
        membership = participant_membership
        return nil if membership.nil?

        role = membership.effective_role_key

        formatter = ChatGem.configuration.role_formatter
        formatted = apply_formatter(formatter, role, self)
        return formatted if formatted.present?

        membership.effective_role_name
      end

      private

      def participant_membership
        return @participant_membership if instance_variable_defined?(:@participant_membership)

        @participant_membership = chat.chat_memberships.active.find_by(participant: participant)
      end

      def formatted_time_for(timestamp)
        formatter = ChatGem.configuration.timestamp_formatter
        formatted = apply_formatter(formatter, timestamp, self)
        return formatted if formatted.present?

        I18n.l(timestamp.in_time_zone, format: :long)
      end

      def apply_formatter(formatter, *args)
        return nil unless formatter.respond_to?(:call)

        case formatter.arity
        when 0
          formatter.call
        when 1
          formatter.call(args.first)
        else
          formatter.call(*args)
        end
      rescue ArgumentError
        nil
      end
    end
  end
end
