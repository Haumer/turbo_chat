module TurboChat
  module ApplicationHelper
    module ParticipantSupport
      def chat_participant_name(participant)
        return "Unknown" if participant.nil?
        return participant.username if participant.respond_to?(:username) && participant.username.present?
        return participant.name if participant.respond_to?(:name) && participant.name.present?
        return participant.email if participant.respond_to?(:email) && participant.email.present?

        participant.to_s
      end

      def own_chat_message?(chat_message, participant: nil)
        return false if chat_message.nil?

        participant ||= current_chat_participant_for_view
        return false if participant.nil?

        participant_type = participant.class.base_class.name
        participant_id = participant.id
        return false if participant_type.blank? || participant_id.blank?

        chat_message.participant_type.to_s == participant_type &&
          chat_message.participant_id.to_s == participant_id.to_s
      end

      def can_edit_chat_message?(chat_message, participant: nil)
        return false if chat_message.nil?

        participant ||= current_chat_participant_for_view
        if participant.nil?
          return true unless respond_to?(:current_chat_participant, true)

          return false
        end

        adapter = TurboChat.configuration.permission_adapter
        return false unless adapter.respond_to?(:new)

        permission = adapter.new(participant, chat_message.chat)
        if permission.respond_to?(:can_edit_message?)
          return permission.can_edit_message?(chat_message)
        end

        return false if permission.respond_to?(:can_post_message?) && !permission.can_post_message?

        own_chat_message?(chat_message, participant: participant)
      rescue StandardError
        false
      end

      private

      def current_chat_participant_for_view
        return nil unless respond_to?(:current_chat_participant, true)

        current_chat_participant
      rescue StandardError
        nil
      end

      def mention_viewer_participant(permission:)
        return permission.participant if permission.respond_to?(:participant) && permission.participant.present?

        current_chat_participant_for_view
      end

      def same_chat_participant?(first, second)
        return false if first.nil? || second.nil?
        return false unless first.respond_to?(:id) && second.respond_to?(:id)

        first_type = first.class.base_class.name
        second_type = second.class.base_class.name
        return false if first_type.blank? || second_type.blank?
        return false if first.id.blank? || second.id.blank?

        first_type == second_type && first.id.to_s == second.id.to_s
      end
    end
  end
end
