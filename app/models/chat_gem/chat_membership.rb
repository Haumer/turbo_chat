module ChatGem
  class ChatMembership < ApplicationRecord
    belongs_to :chat, class_name: "ChatGem::Chat", inverse_of: :chat_memberships
    belongs_to :participant, polymorphic: true

    enum :role, { member: 0, moderator: 1, admin: 2 }, default: :member

    scope :active, -> { where(removed_at: nil) }

    validates :participant_type, :participant_id, presence: true
    validate :enforce_chat_participant_limit, if: :active?
    validate :custom_role_must_exist, if: -> { custom_role_key.present? }

    before_validation :normalize_custom_role_key

    def active?
      removed_at.nil?
    end

    def role_key
      custom_role_key.presence || role
    end

    def role_key=(value)
      normalized = normalize_role_key_value(value)
      if normalized.blank?
        self.custom_role_key = nil
        return
      end

      if self.class.roles.key?(normalized)
        self.role = normalized
        self.custom_role_key = nil
      else
        self.role = :member if role.blank?
        self.custom_role_key = normalized
      end
    end

    def effective_role_key
      role_key.to_s
    end

    def effective_role_definition
      ChatGem.configuration.role_definition(effective_role_key)
    end

    def effective_role_name
      definition = effective_role_definition
      return effective_role_key.humanize if definition.nil?

      definition[:name].presence || effective_role_key.humanize
    end

    def effective_role_rank
      definition = effective_role_definition
      return -1 if definition.nil?

      definition[:rank].to_i
    end

    def effective_role_permissions
      definition = effective_role_definition
      return [] if definition.nil?

      Array(definition[:permissions]).map(&:to_sym)
    end

    private

    def normalize_custom_role_key
      self.custom_role_key = normalize_role_key_value(custom_role_key)
    end

    def custom_role_must_exist
      return if ChatGem.configuration.role_definition(custom_role_key).present?

      errors.add(:custom_role_key, "is not configured")
    end

    def normalize_role_key_value(value)
      value.to_s.strip.presence
    end

    def enforce_chat_participant_limit
      return if chat.nil?

      limit = ChatGem.configuration.max_chat_participants
      return if limit.nil?

      limit = limit.to_i
      return if limit <= 0

      active_count_without_self = chat.chat_memberships.active.where.not(id: id).count
      return if active_count_without_self < limit

      errors.add(:chat, "has reached the participant limit (#{limit})")
    end
  end
end
