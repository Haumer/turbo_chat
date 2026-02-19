module ChatGem
  class ChatsController < ApplicationController
    module InvitationSupport
      private

      def build_invitable_participants
        participant_type = current_chat_participant.class.base_class.name
        participant_class = participant_type.safe_constantize
        return [] if participant_class.nil?
        return [] unless participant_class < ActiveRecord::Base
        return [] unless participant_class.method_defined?(:active_chat_memberships)

        current_member_ids = @chat.chat_memberships.where(removed_at: nil, participant_type: participant_type).pluck(:participant_id)
        participant_class.where.not(id: current_member_ids).order(id: :asc).limit(100).to_a
      rescue StandardError
        []
      end

      def pending_invitations_for(participant)
        return ChatGem::ChatMembership.none if participant.nil?
        return ChatGem::ChatMembership.none unless ChatGem::ChatMembership.invitation_tracking_supported?

        ChatGem::ChatMembership
          .pending
          .where(participant: participant)
          .includes(:chat)
          .order(created_at: :desc, id: :desc)
      end
    end
  end
end
