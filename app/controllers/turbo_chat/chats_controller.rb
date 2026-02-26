module TurboChat
  class ChatsController < ApplicationController
    include TurboChat::ChatsController::InvitationSupport
    include TurboChat::ChatsController::EventPayloadSupport

    before_action :authorize_create_chat!, only: %i[new create]
    before_action :set_chat, only: %i[show accept decline leave close reopen]

    def index
      participant = current_chat_participant
      @chats = TurboChat::Chat.for_participant(participant).order(created_at: :desc, id: :desc)
      @show_members = show_members_enabled?
      @chat_member_counts = if @show_members
                              chat_ids = @chats.except(:order).select(:id)
                              TurboChat::ChatMembership.active.where(chat_id: chat_ids).group(:chat_id).count
                            else
                              {}
                            end
      @pending_invitations = pending_invitations_for(participant)
      @invitation_accepted_event = invitation_accepted_payload
      @chat_lifecycle_event = chat_lifecycle_event_payload
    end

    def accept
      participant = current_chat_participant
      membership = pending_invitation_membership_for(participant, action: "accept")
      return if membership.nil?

      membership.accept_invitation!
      TurboChat::ChatMessage.create_membership_system_message!(
        chat: @chat,
        actor: participant,
        event: :accepted
      )
      flash[:turbo_chat_invitation_accepted] = {
        chatId: @chat.id,
        chatTitle: @chat.title,
        chatMembershipId: membership.id
      }
      set_chat_lifecycle_event(action: :joined, chat: @chat, membership: membership)
      redirect_to chats_path, notice: "Invitation accepted", status: :see_other
    end

    def decline
      participant = current_chat_participant
      membership = pending_invitation_membership_for(participant, action: "decline")
      return if membership.nil?

      remove_membership!(membership, invitation_accepted: false)
      TurboChat::ChatMessage.create_membership_system_message!(
        chat: @chat,
        actor: participant,
        event: :declined
      )
      set_chat_lifecycle_event(action: :declined, chat: @chat, membership: membership)
      redirect_to chats_path, notice: "Invitation declined", status: :see_other
    end

    def new
      @chat = TurboChat::Chat.new
    end

    def create
      @chat = TurboChat::Chat.new(chat_params)

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
      @show_members = show_members_enabled?
      @can_invite_member = @chat_permission.respond_to?(:can_invite_member?) && @chat_permission.can_invite_member?
      @can_manage_member_permissions = @chat_permission.respond_to?(:can_grant_member_permissions?) && @chat_permission.can_grant_member_permissions?
      @can_close_chat = @chat_permission.can_close_chat?
      @can_reopen_chat = @chat_permission.can_reopen_chat?
      @can_edit_own_messages = if @chat_permission.respond_to?(:can_edit_message?)
                                 @chat_permission.can_edit_message?
                               else
                                 @can_post_message
                               end
      @chat_message = @chat.chat_messages.build if @can_post_message
      @invitable_participants = build_invitable_participants if @can_invite_member
      @invite_participant_type = current_chat_participant.class.base_class.name if @can_invite_member
    end

    def leave
      authorize_view_chat!(@chat)
      return if performed?

      participant = current_chat_participant
      membership = @chat.chat_memberships.active.find_by(participant: participant)
      return redirect_to(chats_path, alert: "You are no longer a participant in this chat", status: :see_other) if membership.nil?

      remove_membership!(membership)
      TurboChat::ChatMessage.create_membership_system_message!(
        chat: @chat,
        actor: participant,
        event: :left
      )
      set_chat_lifecycle_event(action: :left, chat: @chat, membership: membership)
      redirect_to chats_path, notice: "You left the chat", status: :see_other
    end

    def close
      transition_chat_state!(
        permission_method: :can_close_chat?,
        mutation: :close!,
        action: :closed,
        notice: "Chat closed"
      )
    end

    def reopen
      transition_chat_state!(
        permission_method: :can_reopen_chat?,
        mutation: :reopen!,
        action: :reopened,
        notice: "Chat reopened"
      )
    end

    private

    def set_chat
      @chat = TurboChat::Chat.find(params[:id])
    end

    def chat_params
      params.require(:chat).permit(:title)
    end

    def show_members_enabled?
      configuration = TurboChat.configuration
      value = configuration.respond_to?(:show_members) ? configuration.show_members : true
      ActiveModel::Type::Boolean.new.cast(value)
    rescue StandardError
      true
    end

    def pending_invitation_membership_for(participant, action:)
      if participant.nil?
        head :forbidden
        return nil
      end
      unless TurboChat::ChatMembership.invitation_tracking_supported?
        redirect_to chats_path, alert: "Run latest turbo_chat migrations to #{action} invitations", status: :see_other
        return nil
      end

      membership = @chat.chat_memberships.pending.find_by(participant: participant)
      return membership if membership.present?

      redirect_to chats_path, alert: "Invitation not found", status: :see_other
      nil
    end

    def remove_membership!(membership, invitation_accepted: nil)
      attributes = { removed_at: Time.current, muted: false, timed_out_until: nil }
      attributes[:invitation_accepted] = invitation_accepted unless invitation_accepted.nil?
      membership.update!(attributes)
    end

    def transition_chat_state!(permission_method:, mutation:, action:, notice:)
      chat_permission = permission_for(@chat)
      return head :forbidden unless chat_permission.public_send(permission_method)

      @chat.public_send(mutation)
      set_chat_lifecycle_event(action: action, chat: @chat)
      redirect_to chat_path(@chat), notice: notice, status: :see_other
    end
  end
end
