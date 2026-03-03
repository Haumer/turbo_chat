class TurboChat::Permission
  module Support
    private

    def can_manage_target_membership?(permission, target_membership)
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

      lookup_membership(target_participant)
    end

    def role_permission?(permission) = role_permissions.include?(permission.to_sym)

    def role_permissions = actor_membership&.effective_role_permissions || []

    def actor_rank = actor_membership&.effective_role_rank || -1

    def target_role_rank(target_membership) = target_membership&.effective_role_rank || -1

    def actor_membership
      return @actor_membership if defined?(@actor_membership)

      @actor_membership = if chat_present? && participant_present?
                            lookup_membership(participant)
                          end
    end

    def participant_present? = !participant.nil?

    def chat_present? = !chat.nil?

    def actor_identity
      return [nil, nil] unless participant_present?

      [participant.class.base_class.name, participant.id]
    end

    def actor_membership_active? = actor_membership&.active?

    def actor_membership_muted? = actor_membership&.muted?

    def actor_membership_timed_out? = actor_membership&.timed_out_until&.future?

    def chat_closed? = chat&.closed?

    def message_in_chat?(message) = message.chat_id == chat&.id

    def membership_in_chat?(target_membership) = target_membership.chat_id == chat&.id

    def lookup_membership(target)
      chat.find_active_membership(target)
    end
  end
end
