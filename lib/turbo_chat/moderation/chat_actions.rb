module TurboChat::Moderation
  module ChatActions
    def delete_message!(actor:, message:)
      permission = permission_for(actor, message.chat)
      authorize_permission!(permission.can_delete_message?(message), "Not allowed to delete message")

      payload = moderation_message_payload(message)
      message.destroy!
      emit_moderation_event("turbo_chat.moderation.message_deleted", actor: actor, payload: payload, chat: message.chat)
      true
    end

    def close_chat!(actor:, chat:)
      update_chat!(
        actor: actor,
        chat: chat,
        gate: :can_close_chat?,
        error_message: "Not allowed to close chat",
        event_name: "turbo_chat.moderation.chat_closed",
        chat_event: :close!
      )
    end

    def reopen_chat!(actor:, chat:)
      update_chat!(
        actor: actor,
        chat: chat,
        gate: :can_reopen_chat?,
        error_message: "Not allowed to reopen chat",
        event_name: "turbo_chat.moderation.chat_reopened",
        chat_event: :reopen!
      )
    end

    private

    def update_chat!(actor:, chat:, gate:, error_message:, event_name:, chat_event:)
      authorize_chat_action!(actor: actor, chat: chat, gate: gate, error_message: error_message)
      chat.public_send(chat_event)
      emit_moderation_event(event_name, actor: actor, payload: moderation_chat_payload(chat), chat: chat)
      chat
    end
  end
end
