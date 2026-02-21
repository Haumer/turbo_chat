module TurboChat
  class ChatMessage < ApplicationRecord
    MENTION_PATTERN = /(?<![[:alnum:]_])@[[:alpha:]][[:alnum:]_]{0,31}/.freeze
    ROLE_MENTION_PATTERN = /\A@[A-Z][A-Z0-9_]{0,31}\z/.freeze
    STREAM_NAME = :messages
    MESSAGE_PARTIAL = "turbo_chat/chat_messages/message"
    CHAT_MESSAGE_PARTIAL = "turbo_chat/chat_messages/chat_message"
    SIGNALS_PARTIAL = "turbo_chat/chat_messages/signals"
    MEMBERSHIP_SYSTEM_EVENT_TYPES = %i[invited accepted declined left muted unmuted timed_out timeout_cleared banned].freeze

    include TurboChat::ChatMessage::BodyLengthValidation
    include TurboChat::ChatMessage::Formatting
    include TurboChat::ChatMessage::MentionValidation
    include TurboChat::ChatMessage::BlockedWordsModeration
    include TurboChat::ChatMessage::Signals
    include TurboChat::ChatMessage::Broadcasting

    belongs_to :chat, class_name: "TurboChat::Chat", inverse_of: :chat_messages
    belongs_to :participant, polymorphic: true

    enum :kind, { message: 0, signal: 1, system: 2 }, default: :message
    enum :signal_type, { typing: 0, thinking: 1, planning: 2 }, prefix: true

    scope :ordered, -> { order(created_at: :asc, id: :asc) }
    scope :messages_only, -> { where(kind: kinds[:message]) }
    scope :timeline, -> { where(kind: [kinds[:message], kinds[:system]].compact) }

    validates :participant_type, :participant_id, presence: true
    validates :body, presence: true, if: -> { message? || system? }
    validates :signal_type, presence: true, if: :signal?
    validate :body_within_max_length, if: :message?
    validate :mentions_allowed_for_participant, if: :message?
    validate :apply_blocked_words_moderation, if: :message?

    before_validation :normalize_signal_fields
    before_create :replace_participant_signals_on_submit, if: :message?

    after_create_commit :broadcast_create
    after_update_commit :broadcast_update
    after_destroy_commit :broadcast_destroy

    class << self
      def create_membership_system_message!(chat:, actor:, event:, subject: nil)
        return nil unless system_messages_enabled?
        return nil if chat.nil? || actor.nil?

        normalized_event = event.to_s.to_sym
        return nil unless MEMBERSHIP_SYSTEM_EVENT_TYPES.include?(normalized_event)

        body = membership_system_message_body(actor: actor, event: normalized_event, subject: subject)
        return nil if body.blank?

        create!(chat: chat, participant: actor, kind: :system, body: body)
      end

      def system_messages_enabled?
        configuration = TurboChat.configuration
        return true unless configuration.respond_to?(:system_messages)

        ActiveModel::Type::Boolean.new.cast(configuration.system_messages)
      rescue StandardError
        true
      end

      private

      def membership_system_message_body(actor:, event:, subject:)
        actor_name = display_name_for_participant(actor)
        subject_name = display_name_for_participant(subject)

        case event
        when :invited
          return nil if actor_name.blank? || subject_name.blank?

          "#{actor_name} invited #{subject_name}."
        when :accepted
          return nil if actor_name.blank?

          "#{actor_name} accepted the invitation."
        when :declined
          return nil if actor_name.blank?

          "#{actor_name} declined the invitation."
        when :left
          return nil if actor_name.blank?

          "#{actor_name} left the chat."
        when :muted
          return nil if actor_name.blank? || subject_name.blank?

          "#{actor_name} muted #{subject_name}."
        when :unmuted
          return nil if actor_name.blank? || subject_name.blank?

          "#{actor_name} unmuted #{subject_name}."
        when :timed_out
          return nil if actor_name.blank? || subject_name.blank?

          "#{actor_name} timed out #{subject_name}."
        when :timeout_cleared
          return nil if actor_name.blank? || subject_name.blank?

          "#{actor_name} cleared timeout for #{subject_name}."
        when :banned
          return nil if actor_name.blank? || subject_name.blank?

          "#{actor_name} removed #{subject_name} from the chat."
        end
      end

      def display_name_for_participant(participant)
        return nil if participant.nil?
        return participant.username if participant.respond_to?(:username) && participant.username.present?
        return participant.name if participant.respond_to?(:name) && participant.name.present?
        return participant.email if participant.respond_to?(:email) && participant.email.present?

        participant.to_s
      end
    end
  end
end
