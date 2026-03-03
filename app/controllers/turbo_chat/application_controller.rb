module TurboChat
  class ApplicationController < ::ApplicationController
    layout "turbo_chat/application"

    helper_method :current_chat_participant

    private

    def current_chat_participant
      participant, source = resolve_current_chat_participant
      return participant if participant.nil? || participant.respond_to?(:active_chat_memberships)

      raise ArgumentError, "#{source} must return a model that uses `acts_as_chat_participant`"
    end

    def resolve_current_chat_participant
      if (super_method = method(:current_chat_participant).super_method)
        return [super_method.call, "#current_chat_participant"]
      end

      resolver = TurboChat.configuration.current_participant_resolver
      if resolver.respond_to?(:call)
        return [invoke_current_participant_resolver(resolver), "TurboChat current_participant_resolver"]
      end

      if respond_to?(:current_user, true)
        return [send(:current_user), "#current_user"]
      end

      raise NotImplementedError, "Define #current_chat_participant, configure TurboChat.configuration.chat.current_participant_resolver, or expose #current_user"
    end

    def invoke_current_participant_resolver(resolver)
      case resolver.arity
      when 0
        resolver.call
      when 1
        resolver.call(self)
      else
        resolver.call(self, request)
      end
    end

    def permission_for(chat = nil)
      TurboChat.configuration.permission_adapter.new(current_chat_participant, chat)
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
      return head(:forbidden) if chat_input_disabled?
      return if permission_for(chat).can_post_message?

      head :forbidden
    end

    def chat_input_disabled?
      TurboChat::Configuration.config_boolean(:disable_input, default: false)
    end
  end
end
