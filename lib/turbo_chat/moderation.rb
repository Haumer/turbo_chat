module TurboChat
  module Moderation
    class AuthorizationError < StandardError; end
    class InvalidActionError < StandardError; end

    class << self
      def mute_member!(actor:, membership:)
        updated_membership = authorize_and_update_membership!(
          actor: actor,
          membership: membership,
          action: :can_mute_member?,
          attributes: { muted: true }
        )

        emit_moderation_event("turbo_chat.moderation.member_muted", actor: actor, membership: updated_membership)
        updated_membership
      end

      def unmute_member!(actor:, membership:)
        updated_membership = authorize_and_update_membership!(
          actor: actor,
          membership: membership,
          action: :can_mute_member?,
          attributes: { muted: false }
        )

        emit_moderation_event("turbo_chat.moderation.member_unmuted", actor: actor, membership: updated_membership)
        updated_membership
      end

      def timeout_member!(actor:, membership:, until_time:)
        authorize_member_action!(actor: actor, membership: membership, action: :can_timeout_member?)
        raise InvalidActionError, "timeout must be in the future" if until_time.nil? || until_time <= Time.current

        membership.update!(timed_out_until: until_time)
        emit_moderation_event(
          "turbo_chat.moderation.member_timed_out",
          actor: actor,
          membership: membership,
          extra: { timed_out_until: membership.timed_out_until }
        )
        membership
      end

      def clear_timeout!(actor:, membership:)
        updated_membership = authorize_and_update_membership!(
          actor: actor,
          membership: membership,
          action: :can_timeout_member?,
          attributes: { timed_out_until: nil }
        )

        emit_moderation_event("turbo_chat.moderation.member_timeout_cleared", actor: actor, membership: updated_membership)
        updated_membership
      end

      def ban_member!(actor:, membership:)
        updated_membership = authorize_and_update_membership!(
          actor: actor,
          membership: membership,
          action: :can_ban_member?,
          attributes: {
            removed_at: Time.current,
            muted: false,
            timed_out_until: nil
          }
        )

        emit_moderation_event("turbo_chat.moderation.member_banned", actor: actor, membership: updated_membership)
        updated_membership
      end

      def delete_message!(actor:, message:)
        permission = permission_for(actor, message.chat)
        authorize_permission!(permission.can_delete_message?(message), "Not allowed to delete message")

        payload = moderation_message_payload(message)
        message.destroy!
        emit_moderation_event("turbo_chat.moderation.message_deleted", actor: actor, payload: payload)
        true
      end

      def close_chat!(actor:, chat:)
        authorize_chat_action!(actor: actor, chat: chat, gate: :can_close_chat?, error_message: "Not allowed to close chat")
        chat.close!
        emit_moderation_event("turbo_chat.moderation.chat_closed", actor: actor, payload: moderation_chat_payload(chat))
        chat
      end

      def reopen_chat!(actor:, chat:)
        authorize_chat_action!(actor: actor, chat: chat, gate: :can_reopen_chat?, error_message: "Not allowed to reopen chat")
        chat.reopen!
        emit_moderation_event("turbo_chat.moderation.chat_reopened", actor: actor, payload: moderation_chat_payload(chat))
        chat
      end

      private

      def authorize_member_action!(actor:, membership:, action:)
        raise InvalidActionError, "membership is required" if membership.nil?

        permission = permission_for(actor, membership.chat)
        return if permission.public_send(action, membership)

        raise AuthorizationError, "Not allowed to #{action.to_s.delete_prefix('can_').delete_suffix('?').tr('_', ' ')}"
      end

      def authorize_and_update_membership!(actor:, membership:, action:, attributes:)
        authorize_member_action!(actor: actor, membership: membership, action: action)
        membership.update!(attributes)
        membership
      end

      def authorize_chat_action!(actor:, chat:, gate:, error_message:)
        permission = permission_for(actor, chat)
        authorize_permission!(permission.public_send(gate), error_message)
      end

      def authorize_permission!(allowed, error_message)
        raise AuthorizationError, error_message unless allowed
      end

      def permission_for(actor, chat)
        TurboChat.configuration.permission_adapter.new(actor, chat)
      end

      def emit_moderation_event(name, actor:, membership: nil, payload: nil, extra: {})
        return unless moderation_events_enabled?
        return unless defined?(ActiveSupport::Notifications)

        base_payload =
          if payload.present?
            payload
          else
            moderation_membership_payload(membership)
          end

        ActiveSupport::Notifications.instrument(
          name,
          base_payload.merge(actor_payload(actor)).merge(extra)
        )
      end

      def moderation_events_enabled?
        config = TurboChat.configuration
        return false unless config.respond_to?(:emit_moderation_events)

        ActiveModel::Type::Boolean.new.cast(config.emit_moderation_events)
      rescue StandardError
        false
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
        return {} if chat.nil?

        {
          chat_id: chat.id,
          closed_at: chat.closed_at
        }
      end

      def actor_payload(actor)
        return { actor_type: nil, actor_id: nil } if actor.nil?

        {
          actor_type: actor.class.base_class.name,
          actor_id: actor.id
        }
      end
    end
  end
end
