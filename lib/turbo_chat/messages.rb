module TurboChat
  module Messages
    class AuthorizationError < StandardError; end
    class InvalidMessageError < StandardError; end
    SEND_MESSAGE_KIND = :message
    VALID_SENT_AT_TYPES = [String, Numeric, Date, Time, DateTime].freeze

    module_function

    def send_message_as(participant, chat, body:, source: TurboChat::ChatMessage::DEFAULT_SOURCE, external_id: nil, sent_at: nil)
      validate_message_inputs!(chat: chat, participant: participant, body: body)
      attributes = normalized_message_attributes(
        body: body,
        source: source,
        external_id: external_id,
        sent_at: sent_at
      )
      authorize_post_message!(participant: participant, chat: chat)

      find_existing_message(chat: chat, source: attributes[:source], external_id: attributes[:external_id]) ||
        create_message!(
          chat: chat,
          participant: participant,
          body: attributes[:body],
          source: attributes[:source],
          external_id: attributes[:external_id],
          sent_at: attributes[:sent_at]
        )
    rescue ActiveRecord::RecordNotUnique
      handle_record_not_unique!(chat: chat, source: attributes[:source], external_id: attributes[:external_id])
    end

    def ingest_external!(chat:, participant:, body:, source:, external_id:, sent_at: nil)
      validate_external_id!(external_id)

      send_message_as(
        participant,
        chat,
        body: body,
        source: source,
        external_id: external_id,
        sent_at: sent_at
      )
    end

    def normalized_message_attributes(body:, source:, external_id:, sent_at:)
      {
        body: body.to_s,
        source: TurboChat::ChatMessage.normalize_source_key(source),
        external_id: TurboChat::ChatMessage.normalize_external_id(external_id),
        sent_at: normalize_sent_at(sent_at)
      }
    end
    private_class_method :normalized_message_attributes

    def find_existing_message(chat:, source:, external_id:)
      return nil if external_id.blank?

      TurboChat::ChatMessage.find_by(chat: chat, source: source, external_id: external_id)
    end
    private_class_method :find_existing_message

    def create_message!(chat:, participant:, body:, source:, external_id:, sent_at:)
      TurboChat::ChatMessage.create!(
        chat: chat,
        participant: participant,
        kind: SEND_MESSAGE_KIND,
        body: body,
        source: source,
        external_id: external_id,
        sent_at: sent_at
      )
    end
    private_class_method :create_message!

    def handle_record_not_unique!(chat:, source:, external_id:)
      return raise if external_id.blank?

      TurboChat::ChatMessage.find_by!(chat: chat, source: source, external_id: external_id)
    end
    private_class_method :handle_record_not_unique!

    def normalize_sent_at(value)
      return nil if value.blank?
      raise InvalidMessageError, "sent_at is invalid" unless valid_sent_at_type?(value)

      parsed = ActiveModel::Type::DateTime.new.cast(value)
      raise InvalidMessageError, "sent_at is invalid" if parsed.nil?

      parsed
    end
    private_class_method :normalize_sent_at

    def valid_sent_at_type?(value)
      VALID_SENT_AT_TYPES.any? { |klass| value.is_a?(klass) } ||
        (defined?(ActiveSupport::TimeWithZone) && value.is_a?(ActiveSupport::TimeWithZone))
    end
    private_class_method :valid_sent_at_type?

    def validate_message_inputs!(chat:, participant:, body:)
      raise InvalidMessageError, "chat is required" if chat.nil?
      raise InvalidMessageError, "participant is required" if participant.nil?
      raise InvalidMessageError, "body is required" if body.to_s.strip.blank?
    end
    private_class_method :validate_message_inputs!

    def validate_external_id!(value)
      return if TurboChat::ChatMessage.normalize_external_id(value).present?

      raise InvalidMessageError, "external_id is required"
    end
    private_class_method :validate_external_id!

    def authorize_post_message!(participant:, chat:)
      permission = permission_for(participant: participant, chat: chat)
      allowed = permission.respond_to?(:can_post_message?) && permission.can_post_message?
      raise AuthorizationError, "Not allowed to post message" unless allowed
    end
    private_class_method :authorize_post_message!

    def permission_for(participant:, chat:)
      adapter = TurboChat.configuration.permission_adapter
      raise AuthorizationError, "permission adapter is not configured" unless adapter.respond_to?(:new)

      adapter.new(participant, chat)
    rescue AuthorizationError
      raise
    rescue StandardError => error
      raise AuthorizationError, "Unable to authorize message posting: #{error.message}"
    end
    private_class_method :permission_for
  end
end
