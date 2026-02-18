module ChatGem
  module Moderation
    class AuthorizationError < StandardError; end
    class InvalidActionError < StandardError; end

    class << self
      def mute_member!(actor:, membership:)
        authorize_and_update_membership!(
          actor: actor,
          membership: membership,
          action: :can_mute_member?,
          attributes: { muted: true }
        )
      end

      def unmute_member!(actor:, membership:)
        authorize_and_update_membership!(
          actor: actor,
          membership: membership,
          action: :can_mute_member?,
          attributes: { muted: false }
        )
      end

      def timeout_member!(actor:, membership:, until_time:)
        authorize_member_action!(actor: actor, membership: membership, action: :can_timeout_member?)
        raise InvalidActionError, "timeout must be in the future" if until_time.nil? || until_time <= Time.current

        membership.update!(timed_out_until: until_time)
        membership
      end

      def clear_timeout!(actor:, membership:)
        authorize_and_update_membership!(
          actor: actor,
          membership: membership,
          action: :can_timeout_member?,
          attributes: { timed_out_until: nil }
        )
      end

      def ban_member!(actor:, membership:)
        authorize_and_update_membership!(
          actor: actor,
          membership: membership,
          action: :can_ban_member?,
          attributes: {
            removed_at: Time.current,
            muted: false,
            timed_out_until: nil
          }
        )
      end

      def delete_message!(actor:, message:)
        permission = permission_for(actor, message.chat)
        authorize_permission!(permission.can_delete_message?(message), "Not allowed to delete message")

        message.destroy!
        true
      end

      def close_chat!(actor:, chat:)
        authorize_chat_action!(actor: actor, chat: chat, gate: :can_close_chat?, error_message: "Not allowed to close chat")
        chat.close!
        chat
      end

      def reopen_chat!(actor:, chat:)
        authorize_chat_action!(actor: actor, chat: chat, gate: :can_reopen_chat?, error_message: "Not allowed to reopen chat")
        chat.reopen!
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
        ChatGem.configuration.permission_adapter.new(actor, chat)
      end
    end
  end
end
