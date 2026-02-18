module ChatGem
  class Permission
    ROLE_MENTION_TOKEN_PATTERN = /\A@[A-Z][A-Z0-9_]{0,31}\z/.freeze
    MEMBER_MENTION_TOKEN_PATTERN = /\A@[a-z0-9_]{1,32}\z/i.freeze

    attr_reader :participant, :chat

    def initialize(participant, chat = nil)
      @participant = participant
      @chat = chat
    end

    def can_view_chat?
      return false unless participant_present?
      return true unless chat_present?
      return false unless actor_membership_active?

      role_permission?(:view_chat)
    end

    def can_create_chat?
      participant_present?
    end

    def can_post_message?
      return false unless can_view_chat?
      return false unless role_permission?(:post_message)
      return false if chat_closed?
      return false if actor_membership_muted?
      return false if actor_membership_timed_out?

      true
    end

    def can_mute_member?(target_membership = nil)
      can_moderate_member?(:mute_member, target_membership)
    end

    def can_timeout_member?(target_membership = nil)
      can_moderate_member?(:timeout_member, target_membership)
    end

    def can_ban_member?(target_membership = nil)
      can_moderate_member?(:ban_member, target_membership)
    end

    def can_invite_member?
      can_view_chat? && role_permission?(:invite_member)
    end

    def can_delete_message?(message = nil)
      return false unless can_view_chat?
      return false unless role_permission?(:delete_message)
      return true if message.nil?
      return false unless message_in_chat?(message)

      target_membership = membership_for(message.participant)
      can_act_on_target_membership?(target_membership)
    end

    def can_edit_message?(message = nil)
      return false unless can_post_message?
      return true if message.nil?
      return false unless message_in_chat?(message)

      participant_type, participant_id = actor_identity
      return false if participant_type.blank? || participant_id.blank?

      message.participant_type.to_s == participant_type &&
        message.participant_id.to_s == participant_id.to_s
    end

    def can_close_chat?
      can_view_chat? && role_permission?(:close_chat)
    end

    def can_reopen_chat?
      can_view_chat? && role_permission?(:reopen_chat)
    end

    def can_mention_members?
      can_view_chat? && role_permission?(:mention_member)
    end

    def can_mention_all?
      can_view_chat? && role_permission?(:mention_all)
    end

    def can_mention_roles?
      can_view_chat? && role_permission?(:mention_role)
    end

    def can_mention_token?(token)
      mention = token.to_s.strip
      return false if mention.blank?
      return false unless mention.start_with?("@")

      return can_mention_all? if mention.casecmp("@all").zero?
      return can_mention_roles? if ROLE_MENTION_TOKEN_PATTERN.match?(mention)
      return can_mention_members? if MEMBER_MENTION_TOKEN_PATTERN.match?(mention)

      false
    end

    private

    def can_moderate_member?(permission, target_membership)
      return false unless can_view_chat?
      return false unless role_permission?(permission)
      return true if target_membership.nil?
      return false unless membership_in_chat?(target_membership)
      return false unless target_membership.active?

      can_act_on_target_membership?(target_membership)
    end

    def can_act_on_target_membership?(target_membership)
      return true if target_membership.nil?
      return false unless actor_membership_active?
      return false if target_membership.participant == participant

      actor_rank > target_role_rank(target_membership)
    end

    def membership_for(target_participant)
      return nil unless chat_present?
      return nil if target_participant.nil?

      chat.chat_memberships.find_by(participant: target_participant)
    end

    def role_permission?(permission)
      role_permissions.include?(permission.to_sym)
    end

    def role_permissions
      actor_membership&.effective_role_permissions || []
    end

    def actor_rank
      actor_membership&.effective_role_rank || -1
    end

    def target_role_rank(target_membership)
      target_membership&.effective_role_rank || -1
    end

    def actor_membership
      return nil unless chat_present?
      return nil unless participant_present?

      chat.chat_memberships.find_by(participant: participant)
    end

    def participant_present?
      !participant.nil?
    end

    def chat_present?
      !chat.nil?
    end

    def actor_identity
      participant_type = participant.class.base_class.name
      participant_id = participant.id
      [participant_type, participant_id]
    end

    def actor_membership_active?
      actor_membership&.active?
    end

    def actor_membership_muted?
      actor_membership&.muted?
    end

    def actor_membership_timed_out?
      actor_membership&.timed_out_until&.future?
    end

    def chat_closed?
      chat&.closed?
    end

    def message_in_chat?(message)
      message.chat_id == chat&.id
    end

    def membership_in_chat?(target_membership)
      target_membership.chat_id == chat&.id
    end
  end
end
