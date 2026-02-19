module TurboChat
  module ModelExtensions
    module ChatParticipant
      module ClassMethods
        def acts_as_chat_participant
          return if reflect_on_association(:chat_memberships).present?

          has_many :chat_memberships,
                   -> { order(created_at: :asc, id: :asc) },
                   as: :participant,
                   class_name: "TurboChat::ChatMembership",
                   dependent: :destroy

          has_many :chat_messages,
                   -> { order(created_at: :asc, id: :asc) },
                   as: :participant,
                   class_name: "TurboChat::ChatMessage",
                   dependent: :destroy

          has_many :chats,
                   -> { distinct },
                   through: :chat_memberships,
                   source: :chat,
                   class_name: "TurboChat::Chat"

          include TurboChat::ModelExtensions::ChatParticipant::InstanceMethods
        end
      end

      module InstanceMethods
        def active_chat_memberships
          chat_memberships.active
        end

        def joined_chat?(chat)
          active_chat_memberships.exists?(chat_id: chat.id)
        end
      end
    end
  end
end

ActiveSupport.on_load(:active_record) do
  extend TurboChat::ModelExtensions::ChatParticipant::ClassMethods
end
