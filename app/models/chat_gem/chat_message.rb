module ChatGem
  class ChatMessage < ApplicationRecord
    MENTION_PATTERN = /(?<![[:alnum:]_])@[[:alpha:]][[:alnum:]_]{0,31}/.freeze
    ROLE_MENTION_PATTERN = /\A@[A-Z][A-Z0-9_]{0,31}\z/.freeze
    STREAM_NAME = :messages
    MESSAGE_PARTIAL = "chat_gem/chat_messages/message"
    CHAT_MESSAGE_PARTIAL = "chat_gem/chat_messages/chat_message"
    SIGNALS_PARTIAL = "chat_gem/chat_messages/signals"

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
          [chat, STREAM_NAME],
          target: ActionView::RecordIdentifier.dom_id(chat, :signals),
          partial: SIGNALS_PARTIAL,
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
      formatted_time_for(created_at)
    end

    def formatted_updated_timestamp
      formatted_time_for(updated_at)
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

      mentions = mention_tokens
      return if mentions.empty?

      permission = mention_permission
      if permission.nil?
        errors.add(:body, "mentions cannot be validated at this time")
        return
      end

      invalid_mention = first_invalid_mention(permission, mentions)
      return if invalid_mention.nil?

      errors.add(:body, mention_permission_error(invalid_mention))
    end

    def apply_blocked_words_moderation
      blocked_words = blocked_words_from_configuration
      return if blocked_words.empty?

      matches = blocked_words_in_body(blocked_words)
      return if matches.empty?

      action = blocked_words_action_from_configuration
      emit_blocked_words_event(
        "chat_gem.blocked_words.detected",
        blocked_words: matches,
        action: action
      )
      if action == "scramble"
        original_body = body.to_s.dup
        scramble_blocked_words!(blocked_words)
        emit_blocked_words_event(
          "chat_gem.blocked_words.scrambled",
          blocked_words: matches,
          action: action,
          original_body: original_body,
          moderated_body: body.to_s
        )
        return
      end

      errors.add(:body, "contains blocked language")
      emit_blocked_words_event(
        "chat_gem.blocked_words.rejected",
        blocked_words: matches,
        action: action
      )
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

      stream = stream_name

      if message? && respond_to?(:broadcast_append_to)
        broadcast_append_to(
          stream,
          target: ActionView::RecordIdentifier.dom_id(chat, :messages),
          partial: CHAT_MESSAGE_PARTIAL,
          locals: { chat_message: self }
        )
      end

      broadcast_update_to(
        stream,
        target: ActionView::RecordIdentifier.dom_id(chat, :signals),
        partial: SIGNALS_PARTIAL,
        locals: { chat: chat }
      )
    end

    def broadcast_update
      return unless message?
      return unless saved_change_to_body?
      return unless respond_to?(:broadcast_replace_to)

      broadcast_replace_to(
        stream_name,
        target: ActionView::RecordIdentifier.dom_id(self),
        partial: MESSAGE_PARTIAL,
        locals: { chat_message: self }
      )
    end

    def broadcast_destroy
      stream = stream_name

      if message? && respond_to?(:broadcast_remove_to)
        broadcast_remove_to(
          stream,
          target: ActionView::RecordIdentifier.dom_id(self)
        )
      end

      self.class.broadcast_signal_refresh(chat)
    end

    def formatted_time_for(timestamp)
      formatter = ChatGem.configuration.timestamp_formatter
      formatted = apply_formatter(formatter, timestamp, self)
      return formatted if formatted.present?

      I18n.l(timestamp.in_time_zone, format: :long)
    end

    def mention_tokens
      body.to_s.scan(MENTION_PATTERN).uniq
    end

    def first_invalid_mention(permission, mentions)
      mentions.find { |mention| !mention_allowed?(permission, mention) }
    end

    def stream_name
      [chat, STREAM_NAME]
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

    def blocked_words_in_body(blocked_words)
      blocked_words.select { |word| blocked_word_pattern(word).match?(body.to_s) }
    end

    def scramble_blocked_words!(blocked_words)
      moderated_body = body.to_s.dup

      blocked_words.each do |word|
        moderated_body.gsub!(blocked_word_pattern(word)) do |match|
          scramble_word(match)
        end
      end

      self.body = moderated_body
    end

    def scramble_word(word)
      source = word.to_s
      characters = source.chars
      return source if characters.length < 2

      scrambled = characters.shuffle
      if scrambled == characters && characters.uniq.length > 1
        scrambled = characters.rotate(1)
      end

      scrambled.join
    end

    def blocked_word_pattern(word)
      /(?<![[:alnum:]_])#{Regexp.escape(word)}(?![[:alnum:]_])/i
    end

    def blocked_words_from_configuration
      configuration = ChatGem.configuration
      return [] unless configuration.respond_to?(:effective_blocked_words)

      Array(configuration.effective_blocked_words)
    rescue StandardError
      []
    end

    def blocked_words_action_from_configuration
      configuration = ChatGem.configuration
      return "reject" unless configuration.respond_to?(:effective_blocked_words_action)

      configuration.effective_blocked_words_action.to_s
    rescue StandardError
      "reject"
    end

    def emit_blocked_words_event(name, blocked_words:, action:, original_body: nil, moderated_body: nil)
      return unless blocked_words_events_enabled?
      return unless defined?(ActiveSupport::Notifications)

      payload = {
        chat_id: chat_id,
        message_id: id,
        participant_type: participant_type,
        participant_id: participant_id,
        blocked_words: Array(blocked_words).map(&:to_s),
        action: action.to_s
      }
      payload[:original_body] = original_body if original_body.present?
      payload[:moderated_body] = moderated_body if moderated_body.present?
      ActiveSupport::Notifications.instrument(name, payload)
    end

    def blocked_words_events_enabled?
      configuration = ChatGem.configuration
      return false unless configuration.respond_to?(:emit_blocked_words_events)

      ActiveModel::Type::Boolean.new.cast(configuration.emit_blocked_words_events)
    rescue StandardError
      false
    end

  end
end
