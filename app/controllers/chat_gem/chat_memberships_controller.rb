module ChatGem
  class ChatMembershipsController < ApplicationController
    before_action :set_chat
    before_action -> { authorize_view_chat!(@chat) }
    before_action :authorize_invite_member!

    def create
      participant = invite_participant
      membership = @chat.chat_memberships.find_or_initialize_by(participant: participant)
      pending_invitation_attributes = invitation_pending_attributes

      if membership.persisted?
        membership.assign_attributes(
          removed_at: nil,
          muted: false,
          timed_out_until: nil
        )
        membership.assign_attributes(pending_invitation_attributes)
      else
        membership.assign_attributes(role: :member)
        membership.assign_attributes(pending_invitation_attributes)
      end

      membership.save!
      redirect_to chat_path(@chat), notice: "Participant invited"
    rescue ActiveRecord::RecordNotFound
      redirect_to chat_path(@chat), alert: "Participant not found"
    rescue NameError, ArgumentError
      redirect_to chat_path(@chat), alert: "Invalid participant type"
    rescue ActiveRecord::RecordInvalid => error
      redirect_to chat_path(@chat), alert: error.record.errors.full_messages.to_sentence
    end

    private

    def set_chat
      @chat = ChatGem::Chat.find(params[:chat_id])
    end

    def authorize_invite_member!
      permission = permission_for(@chat)
      return if permission.respond_to?(:can_invite_member?) && permission.can_invite_member?

      head :forbidden
    end

    def invite_params
      params.require(:chat_membership).permit(:participant_type, :participant_id)
    end

    def invite_participant
      participant_type = invite_params.fetch(:participant_type).to_s
      participant_id = invite_params.fetch(:participant_id).to_s
      raise ArgumentError if participant_type.blank? || participant_id.blank?

      participant_class = participant_type.safe_constantize
      raise NameError if participant_class.nil?
      raise ArgumentError unless participant_class < ActiveRecord::Base
      raise ArgumentError unless participant_class.method_defined?(:active_chat_memberships)
      raise ArgumentError unless invite_type_allowed?(participant_class)

      participant_class.find(participant_id)
    end

    def invite_type_allowed?(participant_class)
      inviter = current_chat_participant
      return false if inviter.nil?

      participant_class.base_class.name == inviter.class.base_class.name
    end

    def invitation_pending_attributes
      return {} unless ChatGem::ChatMembership.invitation_tracking_supported?

      { invitation_accepted: false }
    end
  end
end
