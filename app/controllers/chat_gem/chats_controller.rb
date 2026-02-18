module ChatGem
  class ChatsController < ApplicationController
    before_action :authorize_create_chat!, only: %i[new create]
    before_action :set_chat, only: %i[show leave close reopen]

    def index
      @chats = ChatGem::Chat.for_participant(current_chat_participant).order(created_at: :desc, id: :desc)
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

      active_participant_ids = @chat.chat_memberships.active.where(participant_type: participant_type).pluck(:participant_id)
      participant_class.where.not(id: active_participant_ids).order(id: :asc).limit(100).to_a
    rescue StandardError
      []
    end
  end
end
