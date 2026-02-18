module ChatGem
  class ChatMessage < ApplicationRecord
    belongs_to :chat, class_name: "ChatGem::Chat", inverse_of: :chat_messages
    belongs_to :participant, polymorphic: true

    enum :kind, { message: 0, signal: 1 }, default: :message
    enum :signal_type, { typing: 0, thinking: 1, planning: 2 }, prefix: true

    scope :ordered, -> { order(created_at: :asc, id: :asc) }
    scope :messages_only, -> { where(kind: kinds[:message]) }

    validates :participant_type, :participant_id, presence: true
    validates :body, presence: true, if: :message?
    validates :signal_type, presence: true, if: :signal?

    before_validation :normalize_signal_fields

    after_create_commit :broadcast_create
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
      return participant.name if participant.respond_to?(:name)
      return participant.email if participant.respond_to?(:email)

      participant.to_s
    end

    def formatted_timestamp
      formatter = ChatGem.configuration.timestamp_formatter
      formatted = apply_formatter(formatter, created_at, self)
      return formatted if formatted.present?

      I18n.l(created_at.in_time_zone, format: :long)
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

    def broadcast_create
      stream = [chat, :messages]

      if message?
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

    def broadcast_destroy
      stream = [chat, :messages]

      if message?
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
  end
end
