module ChatGem
  class ChatsController < ApplicationController
    include ChatGem::ChatsController::InvitationSupport
    include ChatGem::ChatsController::EventPayloadSupport

    before_action :authorize_create_chat!, only: %i[new create]
    before_action :set_chat, only: %i[show accept decline leave close reopen]

    def index
      participant = current_chat_participant
      @chats = ChatGem::Chat.for_participant(participant).order(created_at: :desc, id: :desc)
      @pending_invitations = pending_invitations_for(participant)
      @invitation_accepted_event = invitation_accepted_payload
      @chat_lifecycle_event = chat_lifecycle_event_payload
    end

    def accept
      participant = current_chat_participant
      return head :forbidden if participant.nil?
      return redirect_to(chats_path, alert: "Run latest chat_gem migrations to accept invitations", status: :see_other) unless ChatGem::ChatMembership.invitation_tracking_supported?

      membership = @chat.chat_memberships.pending.find_by(participant: participant)
      return redirect_to(chats_path, alert: "Invitation not found", status: :see_other) if membership.nil?

      membership.accept_invitation!
      flash[:chat_gem_invitation_accepted] = {
        chatId: @chat.id,
        chatTitle: @chat.title,
        chatMembershipId: membership.id
      }
      set_chat_lifecycle_event(action: :joined, chat: @chat, membership: membership)
      redirect_to chats_path, notice: "Invitation accepted", status: :see_other
    end

    def decline
      participant = current_chat_participant
      return head :forbidden if participant.nil?
      return redirect_to(chats_path, alert: "Run latest chat_gem migrations to decline invitations", status: :see_other) unless ChatGem::ChatMembership.invitation_tracking_supported?

      membership = @chat.chat_memberships.pending.find_by(participant: participant)
      return redirect_to(chats_path, alert: "Invitation not found", status: :see_other) if membership.nil?

      membership.update!(removed_at: Time.current, muted: false, timed_out_until: nil, invitation_accepted: false)
      redirect_to chats_path, notice: "Invitation declined", status: :see_other
    end

    def new
      @chat = ChatGem::Chat.new
    end

    def create
      @chat = ChatGem::Chat.new(chat_params)

      if @chat.save
        membership = @chat.chat_memberships.create!(participant: current_chat_participant, role: :admin)
        set_chat_lifecycle_event(action: :joined, chat: @chat, membership: membership)
        redirect_to chat_path(@chat), notice: "Chat created"
      else
        render :new, status: :unprocessable_entity
      end
    end

    def show
      authorize_view_chat!(@chat)
      return if performed?

      @chat_lifecycle_event = chat_lifecycle_event_payload
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
      return redirect_to(chats_path, alert: "You are no longer a participant in this chat", status: :see_other) if membership.nil?

      membership.update!(removed_at: Time.current, muted: false, timed_out_until: nil)
      set_chat_lifecycle_event(action: :left, chat: @chat, membership: membership)
      redirect_to chats_path, notice: "You left the chat", status: :see_other
    end

    def close
      chat_permission = permission_for(@chat)
      return head :forbidden unless chat_permission.can_close_chat?

      @chat.close!
      set_chat_lifecycle_event(action: :closed, chat: @chat)
      redirect_to chat_path(@chat), notice: "Chat closed", status: :see_other
    end

    def reopen
      chat_permission = permission_for(@chat)
      return head :forbidden unless chat_permission.can_reopen_chat?

      @chat.reopen!
      redirect_to chat_path(@chat), notice: "Chat reopened", status: :see_other
    end

    private

    def set_chat
      @chat = ChatGem::Chat.find(params[:id])
    end

    def chat_params
      params.require(:chat).permit(:title)
    end
  end
end
