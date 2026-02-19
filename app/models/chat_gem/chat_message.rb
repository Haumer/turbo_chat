module ChatGem
  class ChatMessage < ApplicationRecord
    MENTION_PATTERN = /(?<![[:alnum:]_])@[[:alpha:]][[:alnum:]_]{0,31}/.freeze
    ROLE_MENTION_PATTERN = /\A@[A-Z][A-Z0-9_]{0,31}\z/.freeze
    STREAM_NAME = :messages
    MESSAGE_PARTIAL = "chat_gem/chat_messages/message"
    CHAT_MESSAGE_PARTIAL = "chat_gem/chat_messages/chat_message"
    SIGNALS_PARTIAL = "chat_gem/chat_messages/signals"

    include ChatGem::ChatMessage::BodyLengthValidation
    include ChatGem::ChatMessage::Formatting
    include ChatGem::ChatMessage::MentionValidation
    include ChatGem::ChatMessage::BlockedWordsModeration
    include ChatGem::ChatMessage::Signals
    include ChatGem::ChatMessage::Broadcasting

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
    validate :apply_blocked_words_moderation, if: :message?

    before_validation :normalize_signal_fields
    before_create :replace_participant_signals_on_submit, if: :message?

    after_create_commit :broadcast_create
    after_update_commit :broadcast_update
    after_destroy_commit :broadcast_destroy
  end
end
