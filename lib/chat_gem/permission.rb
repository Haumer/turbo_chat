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
      return false if participant.nil?
      return true if chat.nil?
      return false unless membership&.active?

      role_permission?(:view_chat)
    end

    def can_create_chat?
      !participant.nil?
    end

    def can_post_message?
      return false unless can_view_chat?
      return false unless role_permission?(:post_message)
      return false if chat&.closed?
      return false if membership&.muted?
      return false if membership&.timed_out_until&.future?

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

    def can_delete_message?(message = nil)
      return false unless can_view_chat?
      return false unless role_permission?(:delete_message)
      return true if message.nil?
      return false if message.chat_id != chat&.id

      target_membership = membership_for(message.participant)
      can_act_on_target_membership?(target_membership)
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
      return false if target_membership.chat_id != chat.id
      return false unless target_membership.active?

      can_act_on_target_membership?(target_membership)
    end

    def can_act_on_target_membership?(target_membership)
      return true if target_membership.nil?
      return false unless membership&.active?
      return false if target_membership.participant == participant

      actor_rank > target_role_rank(target_membership)
    end

    def membership_for(target_participant)
      return nil if chat.nil? || target_participant.nil?

      chat.chat_memberships.find_by(participant: target_participant)
    end

    def role_permission?(permission)
      role_permissions.include?(permission.to_sym)
    end

    def role_permissions
      membership&.effective_role_permissions || []
    end

    def actor_rank
      membership&.effective_role_rank || -1
    end

    def target_role_rank(target_membership)
      target_membership&.effective_role_rank || -1
    end

    def membership
      return nil if chat.nil? || participant.nil?

      @membership ||= chat.chat_memberships.find_by(participant: participant)
    end
  end
end
