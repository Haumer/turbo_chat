module ChatGem
  class ChatMessage < ApplicationRecord
    MENTION_PATTERN = /(?<![[:alnum:]_])@[[:alpha:]][[:alnum:]_]{0,31}/.freeze
    ROLE_MENTION_PATTERN = /\A@[A-Z][A-Z0-9_]{0,31}\z/.freeze

    belongs_to :chat, class_name: "ChatGem::Chat", inverse_of: :chat_messages
    belongs_to :participant, polymorphic: true

    enum :kind, { message: 0, signal: 1 }, default: :message
    enum :signal_type, { typing: 0, thinking: 1, planning: 2 }, prefix: true

    scope :ordered, -> { order(created_at: :asc, id: :asc) }
    scope :messages_only, -> { where(kind: kinds[:message]) }

    validates :participant_type, :participant_id, presence: true
    validates :body, presence: true, if: :message?
    validates :signal_type, presence: true, if: :signal?
    validate :body_within_max_length, if: :message?
    validate :mentions_allowed_for_participant, if: :message?

    before_validation :normalize_signal_fields
    before_create :replace_participant_signals_on_submit, if: :message?

    after_create_commit :broadcast_create
    after_update_commit :broadcast_update
    after_destroy_commit :broadcast_destroy

    class << self
      def start_signal!(chat:, participant:, signal_type: :typing)
        create!(chat: chat, participant: participant, kind: :signal, signal_type: signal_type)
      end

      def replace_signal!(chat:, participant:, signal_type: :typing)
        clear_signals!(chat: chat, participant: participant)
        start_signal!(chat: chat, participant: participant, signal_type: signal_type)
      end

      def clear_signals!(chat:, participant:)
        where(chat: chat, participant: participant, kind: kinds[:signal]).delete_all
        broadcast_signal_refresh(chat)
        true
      end

      def with_signal(chat:, participant:, signal_type: :typing)
        replace_signal!(chat: chat, participant: participant, signal_type: signal_type)
        yield
      ensure
        clear_signals!(chat: chat, participant: participant)
      end

      def broadcast_signal_refresh(chat)
        return unless defined?(Turbo::StreamsChannel)

        Turbo::StreamsChannel.broadcast_update_to(
          [chat, :messages],
          target: ActionView::RecordIdentifier.dom_id(chat, :signals),
          partial: "chat_gem/chat_messages/signals",
          locals: { chat: chat }
        )
      end
    end

    def participant_display_name
      return "Unknown" if participant.nil?
      return participant.username if participant.respond_to?(:username) && participant.username.present?
      return participant.name if participant.respond_to?(:name) && participant.name.present?
      return participant.email if participant.respond_to?(:email) && participant.email.present?

      participant.to_s
    end

    def formatted_timestamp
      formatter = ChatGem.configuration.timestamp_formatter
      formatted = apply_formatter(formatter, created_at, self)
      return formatted if formatted.present?

      I18n.l(created_at.in_time_zone, format: :long)
    end

    def formatted_updated_timestamp
      formatter = ChatGem.configuration.timestamp_formatter
      formatted = apply_formatter(formatter, updated_at, self)
      return formatted if formatted.present?

      I18n.l(updated_at.in_time_zone, format: :long)
    end

    def edited?
      return false if created_at.blank? || updated_at.blank?

      updated_at > created_at
    end

    def participant_membership_role
      membership = participant_membership
      return nil if membership.nil?

      membership.effective_role_key
    end

    def formatted_participant_role
      membership = participant_membership
      return nil if membership.nil?

      role = membership.effective_role_key

      formatter = ChatGem.configuration.role_formatter
      formatted = apply_formatter(formatter, role, self)
      return formatted if formatted.present?

      membership.effective_role_name
    end

    private

    def participant_membership
      return @participant_membership if instance_variable_defined?(:@participant_membership)

      @participant_membership = chat.chat_memberships.active.find_by(participant: participant)
    end

    def normalize_signal_fields
      self.signal_type = nil if message?
      self.body = "" if signal?
    end

    def body_within_max_length
      configured_limit = ChatGem.configuration.max_message_length
      return if configured_limit.nil?

      limit = configured_limit.to_i
      return if limit <= 0
      return if body.to_s.length <= limit

      errors.add(:body, "is too long (maximum is #{limit} characters)")
    end

    def mentions_allowed_for_participant
      return unless ChatGem.configuration.enable_mentions

      mentions = body.to_s.scan(MENTION_PATTERN).uniq
      return if mentions.empty?

      permission = mention_permission
      return if permission.nil?

      invalid_mention = mentions.find { |mention| !mention_allowed?(permission, mention) }
      return if invalid_mention.nil?

      errors.add(:body, mention_permission_error(invalid_mention))
    end

    def replace_participant_signals_on_submit
      return unless ChatGem.configuration.replace_signals_on_message_submit
      return if chat_id.blank? || participant_type.blank? || participant_id.blank?

      self.class.where(
        chat_id: chat_id,
        participant_type: participant_type,
        participant_id: participant_id,
        kind: self.class.kinds[:signal]
      ).delete_all
    end

    def broadcast_create
      return unless respond_to?(:broadcast_update_to)

      stream = [chat, :messages]

      if message? && respond_to?(:broadcast_append_to)
        broadcast_append_to(
          stream,
          target: ActionView::RecordIdentifier.dom_id(chat, :messages),
          partial: "chat_gem/chat_messages/chat_message",
          locals: { chat_message: self }
        )
      end

      broadcast_update_to(
        stream,
        target: ActionView::RecordIdentifier.dom_id(chat, :signals),
        partial: "chat_gem/chat_messages/signals",
        locals: { chat: chat }
      )
    end

    def broadcast_update
      return unless message?
      return unless saved_change_to_body?
      return unless respond_to?(:broadcast_replace_to)

      broadcast_replace_to(
        [chat, :messages],
        target: ActionView::RecordIdentifier.dom_id(self),
        partial: "chat_gem/chat_messages/message",
        locals: { chat_message: self }
      )
    end

    def broadcast_destroy
      stream = [chat, :messages]

      if message? && respond_to?(:broadcast_remove_to)
        broadcast_remove_to(
          stream,
          target: ActionView::RecordIdentifier.dom_id(self)
        )
      end

      self.class.broadcast_signal_refresh(chat)
    end

    def apply_formatter(formatter, *args)
      return nil unless formatter.respond_to?(:call)

      case formatter.arity
      when 0
        formatter.call
      when 1
        formatter.call(args.first)
      else
        formatter.call(*args)
      end
    rescue ArgumentError
      nil
    end

    def mention_permission
      adapter = ChatGem.configuration.permission_adapter
      return nil unless adapter.respond_to?(:new)

      adapter.new(participant, chat)
    rescue StandardError
      nil
    end

    def mention_allowed?(permission, mention)
      if permission.respond_to?(:can_mention_token?)
        return permission.can_mention_token?(mention)
      end

      case mention_kind(mention)
      when :all
        permission_gate_allowed?(permission, :can_mention_all?)
      when :role
        permission_gate_allowed?(permission, :can_mention_roles?)
      else
        permission_gate_allowed?(permission, :can_mention_members?)
      end
    rescue StandardError
      false
    end

    def permission_gate_allowed?(permission, method_name)
      return true unless permission.respond_to?(method_name)

      permission.public_send(method_name)
    end

    def mention_kind(mention)
      return :all if mention.casecmp("@all").zero?
      return :role if ROLE_MENTION_PATTERN.match?(mention)

      :member
    end

    def mention_permission_error(mention)
      case mention_kind(mention)
      when :all
        "cannot mention @all"
      when :role
        "cannot mention roles"
      else
        "cannot mention other members"
      end
    end
  end
end
