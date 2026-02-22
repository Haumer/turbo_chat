module TurboChat::Moderation
  module MemberActions
    def mute_member!(actor:, membership:)
      update_member!(
        actor: actor,
        membership: membership,
        action: :can_mute_member?,
        attributes: { muted: true },
        event_name: "turbo_chat.moderation.member_muted",
        system_event: :muted
      )
    end

    def unmute_member!(actor:, membership:)
      update_member!(
        actor: actor,
        membership: membership,
        action: :can_mute_member?,
        attributes: { muted: false },
        event_name: "turbo_chat.moderation.member_unmuted",
        system_event: :unmuted
      )
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
      create_membership_system_message(actor: actor, membership: membership, event: :timed_out)
      membership
    end

    def clear_timeout!(actor:, membership:)
      update_member!(
        actor: actor,
        membership: membership,
        action: :can_timeout_member?,
        attributes: { timed_out_until: nil },
        event_name: "turbo_chat.moderation.member_timeout_cleared",
        system_event: :timeout_cleared
      )
    end

    def ban_member!(actor:, membership:)
      update_member!(
        actor: actor,
        membership: membership,
        action: :can_ban_member?,
        attributes: { removed_at: Time.current, muted: false, timed_out_until: nil },
        event_name: "turbo_chat.moderation.member_banned",
        system_event: :banned
      )
    end

    private

    def update_member!(actor:, membership:, action:, attributes:, event_name:, system_event:)
      updated_membership = authorize_and_update_membership!(
        actor: actor,
        membership: membership,
        action: action,
        attributes: attributes
      )
      emit_moderation_event(event_name, actor: actor, membership: updated_membership)
      create_membership_system_message(actor: actor, membership: updated_membership, event: system_event)
      updated_membership
    end
  end
end
