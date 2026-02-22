require_relative "configuration/defaults"
require_relative "configuration/role_support"
require_relative "configuration/emoji_support"
require_relative "configuration/blocked_words_support"

class TurboChat::Configuration
  include RoleSupport
  include EmojiSupport
  include BlockedWordsSupport

  attr_accessor(*DEFAULTS.keys)

  def initialize
    DEFAULTS.each do |attribute, default_value|
      value = default_value.respond_to?(:call) ? default_value.call : (default_value.dup rescue default_value)
      instance_variable_set("@#{attribute}", value)
    end
    @additional_roles = {}
  end
end
