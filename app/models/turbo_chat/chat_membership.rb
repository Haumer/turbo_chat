module TurboChat
  class ChatMembership < ApplicationRecord
    belongs_to :chat, class_name: "TurboChat::Chat", inverse_of: :chat_memberships
    belongs_to :participant, polymorphic: true

    enum :role, { member: 0, moderator: 1, admin: 2 }, default: :member

    scope :active, lambda {
      base_scope = where(removed_at: nil)
      invitation_tracking_supported? ? base_scope.where(invitation_accepted: true) : base_scope
    }
    scope :pending, lambda {
      return none unless invitation_tracking_supported?

      where(removed_at: nil, invitation_accepted: false)
    }

    validates :participant_type, :participant_id, presence: true
    validates :invitation_accepted, inclusion: { in: [true, false] }, if: :invitation_tracking_supported_for_record?
    validate :enforce_chat_participant_limit, if: :active?
    validate :custom_role_must_exist, if: -> { custom_role_key.present? }

    before_validation :normalize_custom_role_key
    after_commit :broadcast_member_entries_refresh, on: %i[create update]

    class << self
      def invitation_tracking_supported?
        column_names.include?("invitation_accepted")
      rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError
        false
      end
    end

    def active?
      removed_at.nil? && (!self.class.invitation_tracking_supported? || invitation_accepted?)
    end

    def pending?
      removed_at.nil? && self.class.invitation_tracking_supported? && !invitation_accepted?
    end

    def accept_invitation!
      update_attributes = { muted: false, timed_out_until: nil }
      update_attributes[:invitation_accepted] = true if self.class.invitation_tracking_supported?
      update!(update_attributes)
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
      TurboChat.configuration.role_definition(effective_role_key)
    end

    def effective_role_name
      effective_role_definition&.dig(:name).presence || effective_role_key.humanize
    end

    def effective_role_rank
      effective_role_definition&.dig(:rank).to_i
    end

    def effective_role_permissions
      Array(effective_role_definition&.dig(:permissions)).map(&:to_sym)
    end

    private

    def invitation_tracking_supported_for_record?
      self.class.invitation_tracking_supported?
    end

    def normalize_custom_role_key
      self.custom_role_key = normalize_role_key_value(custom_role_key)
    end

    def custom_role_must_exist
      return if TurboChat.configuration.role_definition(custom_role_key).present?

      errors.add(:custom_role_key, "is not configured")
    end

    def normalize_role_key_value(value)
      value.to_s.strip.presence
    end

    def enforce_chat_participant_limit
      return if chat.nil?

      limit = TurboChat.configuration.max_chat_participants
      return if limit.nil?

      limit = limit.to_i
      return if limit <= 0

      active_count_without_self = chat.chat_memberships.active.where.not(id: id).count
      return if active_count_without_self < limit

      errors.add(:chat, "has reached the participant limit (#{limit})")
    end

    def broadcast_member_entries_refresh
      return if chat.nil?
      return unless defined?(Turbo::StreamsChannel)

      Turbo::StreamsChannel.broadcast_update_to(
        [chat, TurboChat::ChatMessage::STREAM_NAME],
        target: ActionView::RecordIdentifier.dom_id(chat, :member_entries),
        partial: "turbo_chat/chats/member_entries",
        locals: { chat: chat }
      )
    end
  end
end
