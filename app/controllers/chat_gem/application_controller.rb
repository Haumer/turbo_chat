module ChatGem
  class ApplicationController < ::ApplicationController
    layout "chat_gem/application"

    helper_method :current_chat_participant

    private

    def current_chat_participant
      method_name = ChatGem.configuration_value(:current_participant_method)
      if respond_to?(method_name, true)
        raw_participant = send(method_name)
        resolved_participant = resolve_chat_participant(raw_participant)

        if resolved_participant.is_a?(String) || resolved_participant.is_a?(Symbol)
          raise ArgumentError, "Resolved chat participant must be a model object, not #{resolved_participant.class}. Configure `current_participant_resolver` to map usernames to records."
        end

        return resolved_participant
      end

      raise NotImplementedError, "Define ##{method_name} in your host application controller"
    end

    def resolve_chat_participant(raw_participant)
      resolver = ChatGem.configuration_value(:current_participant_resolver)
      return raw_participant unless resolver.respond_to?(:call)

      case resolver.arity
      when 0
        resolver.call
      when 1
        resolver.call(raw_participant)
      else
        resolver.call(raw_participant, self)
      end
    end

    def permission_for(chat = nil)
      ChatGem.configuration_value(:permission_adapter).new(current_chat_participant, chat)
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
