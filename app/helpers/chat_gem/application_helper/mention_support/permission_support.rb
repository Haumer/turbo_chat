module ChatGem
  module ApplicationHelper
    module MentionSupport
      module PermissionSupport
        private

        def mention_permission_for(chat)
          return nil unless respond_to?(:current_chat_participant, true)

          participant = current_chat_participant
          return nil if participant.nil?

          ChatGem.configuration.permission_adapter.new(participant, chat)
        rescue StandardError
          nil
        end

        def mention_permission_allows?(permission, method_name)
          return true unless permission.respond_to?(method_name)

          permission.public_send(method_name)
        rescue StandardError
          false
        end
      end
    end
  end
end
