module TurboChat
  class ChatMembershipsController < ApplicationController
    include TurboChat::ChatsController::EventPayloadSupport

    before_action :set_chat
    before_action -> { authorize_view_chat!(@chat) }
    before_action :set_chat_membership, only: :update
    before_action :authorize_invite_member!, only: :create
    before_action :authorize_grant_member_permissions!, only: :update

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
      TurboChat::ChatMessage.create_membership_system_message!(
        chat: @chat,
        actor: current_chat_participant,
        event: :invited,
        subject: participant
      )
      set_chat_lifecycle_event(action: :invited, chat: @chat, membership: membership)
      redirect_to chat_path(@chat), notice: "Participant invited"
    rescue ActiveRecord::RecordNotFound
      redirect_to chat_path(@chat), alert: "Participant not found"
    rescue NameError, ArgumentError
      redirect_to chat_path(@chat), alert: "Invalid participant type"
    rescue ActiveRecord::RecordInvalid => error
      redirect_to chat_path(@chat), alert: error.record.errors.full_messages.to_sentence
    end

    def update
      requested_role_key = update_params.fetch(:role_key).to_s.strip
      return redirect_to(chat_path(@chat), alert: "Role is required") if requested_role_key.blank?
      return redirect_to(chat_path(@chat), alert: "You cannot assign that role") unless role_assignment_allowed?(requested_role_key)

      @chat_membership.update!(role_key: requested_role_key)
      redirect_to chat_path(@chat), notice: "Member permissions updated"
    rescue ActiveRecord::RecordNotFound
      redirect_to chat_path(@chat), alert: "Membership not found"
    rescue ActiveRecord::RecordInvalid => error
      redirect_to chat_path(@chat), alert: error.record.errors.full_messages.to_sentence
    end

    private

    def set_chat
      @chat = TurboChat::Chat.find(params[:chat_id])
    end

    def set_chat_membership
      @chat_membership = @chat.chat_memberships.active.find(params[:id])
    end

    def authorize_invite_member!
      permission = permission_for(@chat)
      return if permission.respond_to?(:can_invite_member?) && permission.can_invite_member?

      head :forbidden
    end

    def authorize_grant_member_permissions!
      permission = permission_for(@chat)
      return if permission.respond_to?(:can_grant_member_permissions?) && permission.can_grant_member_permissions?(@chat_membership)

      head :forbidden
    end

    def invite_params
      params.require(:chat_membership).permit(:participant_type, :participant_id)
    end

    def update_params
      params.require(:chat_membership).permit(:role_key)
    end

    def role_assignment_allowed?(role_key)
      definition = TurboChat.configuration.role_definition(role_key)
      return false if definition.nil?

      actor_membership = @chat.chat_memberships.active.find_by(participant: current_chat_participant)
      return false if actor_membership.nil?

      definition[:rank].to_i <= actor_membership.effective_role_rank
    rescue StandardError
      false
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
      return {} unless TurboChat::ChatMembership.invitation_tracking_supported?

      { invitation_accepted: false }
    end
  end
end
