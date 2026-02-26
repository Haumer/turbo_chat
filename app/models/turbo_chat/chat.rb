module TurboChat
  class Chat < ApplicationRecord
    has_many :chat_memberships,
             class_name: "TurboChat::ChatMembership",
             dependent: :destroy,
             inverse_of: :chat

    has_many :chat_messages,
             class_name: "TurboChat::ChatMessage",
             dependent: :destroy,
             inverse_of: :chat

    validates :title, presence: true

    scope :for_participant, lambda { |participant|
      return none if participant.nil?

      joins(:chat_memberships)
        .merge(TurboChat::ChatMembership.active.where(participant: participant))
        .distinct
    }
    scope :opened, -> { where(closed_at: nil) }
    scope :closed, -> { where.not(closed_at: nil) }

    scope :active, lambda { |window: nil|
      cutoff = Time.current - activity_window_seconds(window)
      joins(:chat_messages)
        .merge(TurboChat::ChatMessage.message.where("#{TurboChat::ChatMessage.table_name}.created_at >= ?", cutoff))
        .distinct
    }

    scope :inactive, lambda { |window: nil|
      where.not(id: active(window: window).select(:id))
    }

    def active_signals(window: 12.seconds)
      cutoff = Time.current - window
      latest_message_at = chat_messages
                          .message
                          .where("created_at >= ?", cutoff)
                          .group(:participant_type, :participant_id)
                          .maximum(:created_at)

      recent = chat_messages.signal.where("created_at >= ?", cutoff).ordered.reverse
      seen = {}
      recent.each_with_object([]) do |message, output|
        participant_key = [message.participant_type, message.participant_id]
        last_message_time = latest_message_at[participant_key]
        next if last_message_time && last_message_time >= message.created_at
        next if seen[participant_key]

        output << message
        seen[participant_key] = true
      end.reverse
    end

    def visible_messages(limit: TurboChat.configuration.message_history_limit)
      relation = chat_messages.timeline
      normalized_limit = normalize_message_limit(limit)
      if normalized_limit
        recent_ids = relation.reorder(created_at: :desc, id: :desc).limit(normalized_limit).select(:id)
        relation = relation.where(id: recent_ids)
      end

      relation.ordered.preload(:participant)
    end

    def last_message_at
      chat_messages.message.maximum(:created_at)
    end

    def active?(window: nil, at: Time.current)
      message_time = last_message_at
      return false if message_time.nil?

      message_time >= at - self.class.activity_window_seconds(window)
    end

    def inactive?(window: nil, at: Time.current)
      !active?(window: window, at: at)
    end

    def closed?
      closed_at.present?
    end

    def opened?
      !closed?
    end

    def close!(at: Time.current)
      update!(closed_at: at)
    end

    def reopen!
      update!(closed_at: nil)
    end

    def self.activity_window_seconds(window = nil)
      value = window.nil? ? TurboChat.configuration.active_chat_window : window
      seconds = value.to_i
      return seconds if seconds.positive?

      raise ArgumentError, "active chat window must be a positive duration"
    end

    private

    def normalize_message_limit(limit)
      return nil if limit.nil?

      normalized = limit.to_i
      return nil if normalized <= 0

      normalized
    end
  end
end
