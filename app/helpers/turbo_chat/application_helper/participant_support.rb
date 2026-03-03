module TurboChat
  module ApplicationHelper
    module ParticipantSupport
      def chat_participant_name(participant)
        TurboChat::ParticipantIdentity.display_name(participant)
      end

      def chat_participant_email(participant)
        TurboChat::ParticipantIdentity.email(participant)
      end

      def chat_participant_invite_option_label(participant)
        participant_name = chat_participant_name(participant)
        participant_email = chat_participant_email(participant)
        participant_id_label = participant.respond_to?(:id) && participant.id.present? ? "##{participant.id}" : "unknown"
        return "#{participant_name} (#{participant_id_label})" unless participant_email.present? && participant_email != participant_name

        "#{participant_name} - #{participant_email} (#{participant_id_label})"
      end

      def chat_participant_search_text(participant)
        participant_name = chat_participant_name(participant)
        participant_email = chat_participant_email(participant)
        participant_id = participant.respond_to?(:id) ? participant.id : nil

        [participant_name, participant_email, participant_id].compact_blank.join(" ")
      end

      def own_chat_message?(chat_message, participant: nil)
        return false if chat_message.nil?

        participant ||= current_chat_participant_for_view
        participant_identity = participant_identity_for(participant)
        return false if participant_identity.nil?

        [chat_message.participant_type.to_s, chat_message.participant_id.to_s] == participant_identity
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
      rescue NoMethodError, TypeError
        false
      end

      private

      def current_chat_participant_for_view
        return nil unless respond_to?(:current_chat_participant, true)

        current_chat_participant
      rescue NoMethodError, TypeError
        nil
      end

      def mention_viewer_participant(permission:)
        return permission.participant if permission.respond_to?(:participant) && permission.participant.present?

        current_chat_participant_for_view
      end

      def same_chat_participant?(first, second)
        first_identity = participant_identity_for(first)
        second_identity = participant_identity_for(second)
        first_identity.present? && first_identity == second_identity
      end

      def participant_identity_for(participant)
        return nil unless participant.respond_to?(:id)

        participant_type = participant.class.base_class.name
        participant_id = participant.id
        return nil if participant_type.blank? || participant_id.blank?

        [participant_type, participant_id.to_s]
      end
    end
  end
end
