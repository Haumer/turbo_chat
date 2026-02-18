module ChatGem
  class ChatMessagesController < ApplicationController
    before_action :set_chat
    before_action -> { authorize_view_chat!(@chat) }, only: :index
    before_action -> { authorize_post_message!(@chat) }, only: :create

    def index
      @chat_messages = @chat.visible_messages
    end

    def create
      if clear_signal_request?
        ChatGem::ChatMessage.clear_signals!(chat: @chat, participant: current_chat_participant)
        respond_to do |format|
          format.turbo_stream { render_signals_update }
          format.html { redirect_to chat_path(@chat) }
        end
        return
      end

      @chat_message = @chat.chat_messages.build(chat_message_params)
      @chat_message.participant = current_chat_participant

      if @chat_message.save
        respond_to do |format|
          format.turbo_stream do
            if signal_request?
              render_signals_update
            else
              head :ok
            end
          end
          format.html { redirect_to chat_path(@chat) }
        end
      else
        @chat_messages = @chat.visible_messages
        @chat_permission = permission_for(@chat)
        @can_post_message = @chat_permission.can_post_message?
        respond_to do |format|
          format.turbo_stream { render "chat_gem/chats/show", status: :unprocessable_entity }
          format.html { render "chat_gem/chats/show", status: :unprocessable_entity }
        end
      end
    end

    private

    def set_chat
      @chat = ChatGem::Chat.find(params[:chat_id])
    end

    def chat_message_params
      params.require(:chat_message).permit(:body, :kind, :signal_type)
    end

    def signal_request?
      params.dig(:chat_message, :kind).to_s == "signal"
    end

    def clear_signal_request?
      return false unless signal_request?

      ActiveModel::Type::Boolean.new.cast(params.dig(:chat_message, :clear))
    end

    def render_signals_update
      render turbo_stream: turbo_stream.update(
        view_context.dom_id(@chat, :signals),
        partial: "chat_gem/chat_messages/signals",
        locals: { chat: @chat }
      )
    end
  end
end
