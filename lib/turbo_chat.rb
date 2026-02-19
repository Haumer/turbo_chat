require "turbo_chat/version"
require "turbo-rails"
require "turbo_chat/configuration"
require "turbo_chat/model_extensions/chat_participant"
require "turbo_chat/permission"
require "turbo_chat/moderation"
require "turbo_chat/signals"
require "turbo_chat/engine"

module TurboChat
  class << self
    def configuration
      @configuration ||= TurboChat::Configuration.new
    end

    def configure
      yield(configuration)
    end
  end
end
