module TurboChat
  class ChatMessagesController < ApplicationController
    before_action :set_chat
    before_action -> { authorize_view_chat!(@chat) }, only: :index
    before_action -> { authorize_post_message!(@chat) }, only: :create
    before_action :set_chat_message, only: :update
    before_action :authorize_edit_chat_message!, only: :update

    def index
      @chat_messages = @chat.visible_messages
    end

    def create
      return respond_to_clear_signal_request if clear_signal_request?

      build_chat_message
      @chat_message.save ? respond_to_chat_message_create_success : respond_to_chat_message_create_failure
    end

    def update
      updated = @chat_message.update(edit_chat_message_params)
      if turbo_stream_request?
        return render_chat_message_update(force_edit_open: !updated, status: updated ? :ok : :unprocessable_entity)
      end

      if updated
        redirect_to chat_path(@chat), notice: "Message updated"
      else
        redirect_to chat_path(@chat), alert: @chat_message.errors.full_messages.to_sentence
      end
    end

    private

    def set_chat = @chat = TurboChat::Chat.find(params[:chat_id])

    def chat_message_params
      permitted = params.require(:chat_message).permit(:body, :kind, :signal_type, :signal_text)
      normalized_kind = normalize_submittable_message_kind(permitted[:kind])
      permitted[:kind] = normalized_kind
      signal_text = permitted.delete(:signal_text)
      if normalized_kind == "signal" && !signal_text.nil?
        permitted[:body] = signal_text
      elsif normalized_kind != "signal"
        permitted[:signal_type] = nil
      end
      permitted
    end

    def edit_chat_message_params = params.require(:chat_message).permit(:body)

    def signal_request? = params.dig(:chat_message, :kind).to_s == "signal"

    def clear_signal_request?
      return false unless signal_request?

      ActiveModel::Type::Boolean.new.cast(params.dig(:chat_message, :clear))
    end

    def build_chat_message
      @chat_message = @chat.chat_messages.build(chat_message_params)
      @chat_message.participant = current_chat_participant
    end

    def respond_to_clear_signal_request
      TurboChat::ChatMessage.clear_signals!(chat: @chat, participant: current_chat_participant)
      respond_to do |format|
        format.turbo_stream { render_signals_update }
        format.html { redirect_to chat_path(@chat) }
      end
    end

    def respond_to_chat_message_create_success
      respond_to do |format|
        format.turbo_stream do
          signal_request? ? render_signals_update : head(:ok)
        end
        format.html { redirect_to chat_path(@chat) }
      end
    end

    def respond_to_chat_message_create_failure
      @chat_messages = @chat.visible_messages
      @chat_permission = permission_for(@chat)
      @can_post_message = @chat_permission.can_post_message? && !chat_input_disabled?
      @show_members = chat_config_boolean(:show_members, default: true)
      respond_to do |format|
        format.turbo_stream { render "turbo_chat/chats/show", status: :unprocessable_entity }
        format.html { render "turbo_chat/chats/show", status: :unprocessable_entity }
      end
    end

    def render_signals_update
      render turbo_stream: turbo_stream.update(
        view_context.dom_id(@chat, :signals),
        method: :morph,
        partial: "turbo_chat/chat_messages/signals",
        locals: { chat: @chat }
      )
    end

    def set_chat_message = @chat_message = @chat.chat_messages.messages_only.find(params[:id])

    def authorize_edit_chat_message!
      return if can_edit_chat_message?(permission_for(@chat))

      respond_to do |format|
        format.html { redirect_to chat_path(@chat), alert: "Not allowed to edit this message" }
        format.any { head :forbidden }
      end
    end

    def can_edit_chat_message?(chat_permission)
      return chat_permission.can_edit_message?(@chat_message) if chat_permission.respond_to?(:can_edit_message?)

      fallback_edit_allowed?(chat_permission) && message_owned_by_current_participant?
    end

    def fallback_edit_allowed?(chat_permission)
      return chat_permission.can_post_message? if chat_permission.respond_to?(:can_post_message?)
      return chat_permission.can_view_chat? if chat_permission.respond_to?(:can_view_chat?)

      false
    end

    def message_owned_by_current_participant?
      participant = current_chat_participant
      return false if participant.nil?

      @chat_message.participant_type.to_s == participant.class.base_class.name &&
        @chat_message.participant_id.to_s == participant.id.to_s
    end

    def render_chat_message_update(force_edit_open: false, status: :ok)
      locals = { chat_message: @chat_message }
      locals[:force_edit_open] = true if force_edit_open
      render turbo_stream: turbo_stream.replace(
        view_context.dom_id(@chat_message),
        partial: "turbo_chat/chat_messages/message",
        locals: locals
      ), status: status
    end

    def turbo_stream_request? = request.headers["Accept"].to_s.include?("turbo-stream")

    def normalize_submittable_message_kind(kind) = kind.to_s == "signal" ? "signal" : "message"

    def chat_config_boolean(method_name, default:)
      TurboChat::Configuration.config_boolean(method_name, default: default)
    end
  end
end
