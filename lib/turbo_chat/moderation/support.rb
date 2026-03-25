module TurboChat::Moderation
  module Support
    private

    def authorize_member_action!(actor:, membership:, action:)
      raise InvalidActionError, "membership is required" if membership.nil?

      permission = permission_for(actor, membership.chat)
      return if permission.public_send(action, membership)

      action_name = action.to_s.delete_prefix("can_").delete_suffix("?").tr("_", " ")
      raise AuthorizationError, "Not allowed to #{action_name}"
    end

    def authorize_and_update_membership!(actor:, membership:, action:, attributes:)
      authorize_member_action!(actor: actor, membership: membership, action: action)
      membership.update!(attributes)
      membership
    end

    def authorize_chat_action!(actor:, chat:, gate:, error_message:)
      authorize_permission!(permission_for(actor, chat).public_send(gate), error_message)
    end

    def authorize_permission!(allowed, error_message)
      raise AuthorizationError, error_message unless allowed
    end

    def permission_for(actor, chat) = TurboChat.configuration.permission_adapter.new(actor, chat)

    def create_membership_system_message(actor:, membership:, event:)
      TurboChat::ChatMessage.create_membership_system_message!(
        chat: membership.chat,
        actor: actor,
        event: event,
        subject: membership.participant
      )
    end

    def emit_moderation_event(name, actor:, membership: nil, payload: nil, extra: {}, chat: nil)
      event_chat = chat || membership&.chat
      return unless moderation_events_enabled?(event_chat)
      return unless defined?(ActiveSupport::Notifications)

      event_payload = payload.presence || moderation_membership_payload(membership)
      ActiveSupport::Notifications.instrument(name, event_payload.merge(actor_payload(actor)).merge(extra))
    end

    def moderation_events_enabled?(chat = nil)
      TurboChat::Configuration.config_boolean(:emit_moderation_events, default: false, chat: chat)
    end

    def moderation_membership_payload(membership)
      return {} if membership.nil?

      {
        chat_id: membership.chat_id,
        membership_id: membership.id,
        participant_type: membership.participant_type,
        participant_id: membership.participant_id
      }
    end

    def moderation_message_payload(message)
      return {} if message.nil?

      {
        chat_id: message.chat_id,
        message_id: message.id,
        participant_type: message.participant_type,
        participant_id: message.participant_id
      }
    end

    def moderation_chat_payload(chat)
      chat.nil? ? {} : { chat_id: chat.id, closed_at: chat.closed_at }
    end

    def actor_payload(actor)
      actor.nil? ? { actor_type: nil, actor_id: nil } : { actor_type: actor.class.base_class.name, actor_id: actor.id }
    end
  end
end
