module ChatGem
  class ChatsController < ApplicationController
    before_action :authorize_create_chat!, only: %i[new create]
    before_action :set_chat, only: :show

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

      @chat_permission = permission_for(@chat)
      @chat_messages = @chat.visible_messages
      @can_post_message = @chat_permission.can_post_message?
      @chat_message = @chat.chat_messages.build if @can_post_message
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
