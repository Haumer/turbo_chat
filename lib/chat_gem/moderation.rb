module ChatGem
  module Moderation
    class AuthorizationError < StandardError; end
    class InvalidActionError < StandardError; end

    class << self
      def mute_member!(actor:, membership:)
        authorize_member_action!(actor: actor, membership: membership, action: :can_mute_member?)
        membership.update!(muted: true)
        membership
      end

      def unmute_member!(actor:, membership:)
        authorize_member_action!(actor: actor, membership: membership, action: :can_mute_member?)
        membership.update!(muted: false)
        membership
      end

      def timeout_member!(actor:, membership:, until_time:)
        authorize_member_action!(actor: actor, membership: membership, action: :can_timeout_member?)
        raise InvalidActionError, "timeout must be in the future" if until_time.nil? || until_time <= Time.current

        membership.update!(timed_out_until: until_time)
        membership
      end

      def clear_timeout!(actor:, membership:)
        authorize_member_action!(actor: actor, membership: membership, action: :can_timeout_member?)
        membership.update!(timed_out_until: nil)
        membership
      end

      def ban_member!(actor:, membership:)
        authorize_member_action!(actor: actor, membership: membership, action: :can_ban_member?)
        membership.update!(removed_at: Time.current, muted: false, timed_out_until: nil)
        membership
      end

      def delete_message!(actor:, message:)
        permission = permission_for(actor, message.chat)
        raise AuthorizationError, "Not allowed to delete message" unless permission.can_delete_message?(message)

        message.destroy!
        true
      end

      def close_chat!(actor:, chat:)
        permission = permission_for(actor, chat)
        raise AuthorizationError, "Not allowed to close chat" unless permission.can_close_chat?

        chat.close!
        chat
      end

      def reopen_chat!(actor:, chat:)
        permission = permission_for(actor, chat)
        raise AuthorizationError, "Not allowed to reopen chat" unless permission.can_reopen_chat?

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

      def permission_for(actor, chat)
        ChatGem.configuration_value(:permission_adapter).new(actor, chat)
      end
    end
  end
end
