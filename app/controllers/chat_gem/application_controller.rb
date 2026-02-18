module ChatGem
  class ApplicationController < ::ApplicationController
    layout "chat_gem/application"

    helper_method :current_chat_participant

    private

    def current_chat_participant
      method_name = :chat_current_participant
      raise NotImplementedError, "Define ##{method_name} in your host application controller" unless respond_to?(method_name, true)

      participant = send(method_name)
      return participant if participant.nil? || participant.respond_to?(:active_chat_memberships)

      raise ArgumentError, "##{method_name} must return a model that uses `acts_as_chat_participant`"
    end

    def permission_for(chat = nil)
      ChatGem.configuration.permission_adapter.new(current_chat_participant, chat)
    end

    def authorize_create_chat!
      return if permission_for.can_create_chat?

      head :forbidden
    end

    def authorize_view_chat!(chat)
      return if permission_for(chat).can_view_chat?

      head :forbidden
    end

    def authorize_post_message!(chat)
      return if permission_for(chat).can_post_message?

      head :forbidden
    end
  end
end
