module TurboChat
  class ChatMessage < ApplicationRecord
    MENTION_PATTERN = /(?<![[:alnum:]_])@[[:alpha:]][[:alnum:]_]{0,31}/.freeze
    ROLE_MENTION_PATTERN = /\A@[A-Z][A-Z0-9_]{0,31}\z/.freeze
    SOURCE_KEY_PATTERN = /\A[a-z0-9][a-z0-9_-]{0,31}\z/.freeze
    STREAM_NAME = :messages
    MESSAGE_PARTIAL = "turbo_chat/chat_messages/message"
    CHAT_MESSAGE_PARTIAL = "turbo_chat/chat_messages/chat_message"
    SIGNALS_PARTIAL = "turbo_chat/chat_messages/signals"
    MEMBERSHIP_SYSTEM_MESSAGE_TEMPLATES = {
      invited: "%{actor} invited %{subject}.",
      accepted: "%{actor} accepted the invitation.",
      declined: "%{actor} declined the invitation.",
      left: "%{actor} left the chat.",
      muted: "%{actor} muted %{subject}.",
      unmuted: "%{actor} unmuted %{subject}.",
      timed_out: "%{actor} timed out %{subject}.",
      timeout_cleared: "%{actor} cleared timeout for %{subject}.",
      banned: "%{actor} removed %{subject} from the chat."
    }.freeze
    MEMBERSHIP_SYSTEM_EVENTS_WITH_SUBJECT = %i[invited muted unmuted timed_out timeout_cleared banned].freeze
    MEMBERSHIP_SYSTEM_EVENT_TYPES = MEMBERSHIP_SYSTEM_MESSAGE_TEMPLATES.keys.freeze
    DEFAULT_SOURCE = "app".freeze

    include TurboChat::ChatMessage::BodyLengthValidation
    include TurboChat::ChatMessage::Formatting
    include TurboChat::ChatMessage::MentionValidation
    include TurboChat::ChatMessage::BlockedWordsModeration
    include TurboChat::ChatMessage::Signals
    include TurboChat::ChatMessage::Broadcasting

    belongs_to :chat, class_name: "TurboChat::Chat", inverse_of: :chat_messages
    belongs_to :participant, polymorphic: true

    enum :kind, { message: 0, signal: 1, system: 2 }, default: :message
    enum :signal_type, { typing: 0, thinking: 1, planning: 2, custom: 3 }, prefix: true

    scope :ordered, -> { order(created_at: :asc, id: :asc) }
    scope :messages_only, -> { where(kind: kinds[:message]) }
    scope :timeline, -> { where(kind: [kinds[:message], kinds[:system]].compact) }

    validates :participant_type, :participant_id, presence: true
    validates :source, presence: true, format: { with: SOURCE_KEY_PATTERN }
    validates :body, presence: true, if: -> { message? || system? }
    validates :signal_type, presence: true, if: :signal?
    validates :signal_text, presence: true, if: :custom_signal?
    validates :external_id, uniqueness: { scope: %i[chat_id source] }, allow_nil: true
    validate :body_within_max_length, if: :message?
    validate :mentions_allowed_for_participant, if: :message?
    validate :apply_blocked_words_moderation, if: :message?

    before_validation :normalize_source
    before_validation :normalize_external_id
    before_validation :normalize_signal_fields
    before_create :replace_participant_signals_on_submit, if: :message?

    after_create_commit :broadcast_create
    after_update_commit :broadcast_update
    after_destroy_commit :broadcast_destroy

    def signal_text
      return nil unless signal?

      body.presence
    end

    def signal_text=(value)
      self.body = value
    end

    class << self
      def normalize_source_key(value)
        normalized = value.to_s.strip.downcase
        return DEFAULT_SOURCE if normalized.blank?

        normalized
      end

      def normalize_external_id(value)
        value.to_s.strip.presence
      end

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
        template = MEMBERSHIP_SYSTEM_MESSAGE_TEMPLATES[event]
        return nil if template.nil?

        actor_name = display_name_for_participant(actor)
        return nil if actor_name.blank?

        subject_name = display_name_for_participant(subject)
        return nil if MEMBERSHIP_SYSTEM_EVENTS_WITH_SUBJECT.include?(event) && subject_name.blank?

        format(template, actor: actor_name, subject: subject_name)
      end

      def display_name_for_participant(participant)
        TurboChat::ParticipantIdentity.display_name(participant, unknown: nil)
      end
    end

    private

    def custom_signal?
      signal? && signal_type_custom?
    end

    def normalize_source
      self.source = self.class.normalize_source_key(source)
    end

    def normalize_external_id
      self.external_id = self.class.normalize_external_id(external_id)
    end
  end
end
