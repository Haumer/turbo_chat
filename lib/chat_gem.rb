require "chat_gem/version"
require "chat_gem/configuration"
require "chat_gem/model_extensions/chat_participant"
require "chat_gem/permission"
require "chat_gem/moderation"
require "chat_gem/signals"
require "chat_gem/engine"

module ChatGem
  class << self
    def configuration
      @configuration ||= ChatGem::Configuration.new
    end

    def configure
      yield(configuration)
    end
  end

  def self.table_name_prefix
    "chat_gem_"
  end
end
