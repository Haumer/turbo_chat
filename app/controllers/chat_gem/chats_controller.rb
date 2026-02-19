module ChatGem
  class ChatsController < ApplicationController
    before_action :authorize_create_chat!, only: %i[new create]
    before_action :set_chat, only: %i[show accept decline leave close reopen]

    def index
      participant = current_chat_participant
      @chats = ChatGem::Chat.for_participant(participant).order(created_at: :desc, id: :desc)
      @pending_invitations = pending_invitations_for(participant)
      @invitation_accepted_event = invitation_accepted_payload
    end

    def accept
      participant = current_chat_participant
      return head :forbidden if participant.nil?
      return redirect_to(chats_path, alert: "Run latest chat_gem migrations to accept invitations") unless ChatGem::ChatMembership.invitation_tracking_supported?

      membership = @chat.chat_memberships.pending.find_by(participant: participant)
      return redirect_to chats_path, alert: "Invitation not found" if membership.nil?

      membership.accept_invitation!
      flash[:chat_gem_invitation_accepted] = {
        chatId: @chat.id,
        chatTitle: @chat.title,
        chatMembershipId: membership.id
      }
      redirect_to chats_path, notice: "Invitation accepted"
    end

    def decline
      participant = current_chat_participant
      return head :forbidden if participant.nil?
      return redirect_to(chats_path, alert: "Run latest chat_gem migrations to decline invitations") unless ChatGem::ChatMembership.invitation_tracking_supported?

      membership = @chat.chat_memberships.pending.find_by(participant: participant)
      return redirect_to chats_path, alert: "Invitation not found" if membership.nil?

      membership.update!(removed_at: Time.current, muted: false, timed_out_until: nil, invitation_accepted: false)
      redirect_to chats_path, notice: "Invitation declined"
    end

    def new
      @chat = ChatGem::Chat.new
    end

    def create
      @chat = ChatGem::Chat.new(chat_params)

      if @chat.save
        @chat.chat_memberships.create!(participant: current_chat_participant, role: :admin)
        redirect_to chat_path(@chat), notice: "Chat created"
      else
        render :new, status: :unprocessable_entity
      end
    end

    def show
      authorize_view_chat!(@chat)
      return if performed?

      @chat_permission = permission_for(@chat)
      @chat_messages = @chat.visible_messages
      @can_post_message = @chat_permission.can_post_message?
      @can_invite_member = @chat_permission.respond_to?(:can_invite_member?) && @chat_permission.can_invite_member?
      @can_close_chat = @chat_permission.can_close_chat?
      @can_reopen_chat = @chat_permission.can_reopen_chat?
      @can_edit_own_messages = if @chat_permission.respond_to?(:can_edit_message?)
                                 @chat_permission.can_edit_message?
                               else
                                 @chat_permission.can_post_message?
                               end
      @chat_message = @chat.chat_messages.build if @can_post_message
      @invitable_participants = build_invitable_participants if @can_invite_member
      @invite_participant_type = current_chat_participant.class.base_class.name if @can_invite_member
    end

    def leave
      authorize_view_chat!(@chat)
      return if performed?

      membership = @chat.chat_memberships.active.find_by(participant: current_chat_participant)
      return redirect_to chats_path, alert: "You are no longer a participant in this chat" if membership.nil?

      membership.update!(removed_at: Time.current, muted: false, timed_out_until: nil)
      redirect_to chats_path, notice: "You left the chat"
    end

    def close
      chat_permission = permission_for(@chat)
      return head :forbidden unless chat_permission.can_close_chat?

      @chat.close!
      redirect_to chat_path(@chat), notice: "Chat closed"
    end

    def reopen
      chat_permission = permission_for(@chat)
      return head :forbidden unless chat_permission.can_reopen_chat?

      @chat.reopen!
      redirect_to chat_path(@chat), notice: "Chat reopened"
    end

    private

    def set_chat
      @chat = ChatGem::Chat.find(params[:id])
    end

    def chat_params
      params.require(:chat).permit(:title)
    end

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

    def invitation_accepted_payload
      payload = flash[:chat_gem_invitation_accepted]
      return nil unless payload.respond_to?(:to_h)

      symbolized_payload = payload.to_h.symbolize_keys
      chat_id = symbolized_payload[:chatId].presence || symbolized_payload[:chat_id].presence
      return nil if chat_id.blank?

      {
        chatId: chat_id.to_s,
        chatTitle: symbolized_payload[:chatTitle].presence || symbolized_payload[:chat_title].presence,
        chatMembershipId: symbolized_payload[:chatMembershipId].presence || symbolized_payload[:chat_membership_id].presence
      }.compact
    rescue StandardError
      nil
    end
  end
end
