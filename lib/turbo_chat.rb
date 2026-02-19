require_relative "chat_gem"
require_relative "turbo_chat/version"

module TurboChat
  class << self
    def configuration
      ChatGem.configuration
    end

    def configure(&block)
      ChatGem.configure(&block)
    end

    def table_name_prefix
      ChatGem.table_name_prefix
    end

    def const_missing(name)
      return ChatGem.const_get(name) if ChatGem.const_defined?(name)

      super
    end
  end
end
