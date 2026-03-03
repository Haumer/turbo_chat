require_relative "configuration/defaults"
require_relative "configuration/role_support"
require_relative "configuration/emoji_support"
require_relative "configuration/blocked_words_support"

class TurboChat::Configuration
  include RoleSupport
  include EmojiSupport
  include BlockedWordsSupport

  class Scope
    class << self
      attr_reader :scope_defaults

      def configure_defaults(defaults)
        @scope_defaults = defaults
        attr_accessor(*defaults.keys)
      end
    end

    def initialize
      self.class.scope_defaults.each do |attribute, default_value|
        instance_variable_set("@#{attribute}", TurboChat::Configuration.resolve_default_value(default_value))
      end
    end
  end

  class Chat < Scope
    configure_defaults(SCOPED_DEFAULTS.fetch(:chat))
  end

  class ChatMessage < Scope
    configure_defaults(SCOPED_DEFAULTS.fetch(:chat_message))
  end

  class Style < Scope
    configure_defaults(SCOPED_DEFAULTS.fetch(:style))
  end

  class Moderation < Scope
    configure_defaults(SCOPED_DEFAULTS.fetch(:moderation))
  end

  class Events < Scope
    configure_defaults(SCOPED_DEFAULTS.fetch(:events))
  end

  class Signals < Scope
    configure_defaults(SCOPED_DEFAULTS.fetch(:signals))
  end

  SCOPE_CLASSES = {
    chat: Chat,
    chat_message: ChatMessage,
    style: Style,
    moderation: Moderation,
    events: Events,
    signals: Signals
  }.freeze

  attr_reader(*SCOPE_NAMES)

  ATTRIBUTE_SCOPES.each do |attribute, scope_name|
    define_method(attribute) do
      public_send(scope_name).public_send(attribute)
    end

    define_method("#{attribute}=") do |value|
      public_send(scope_name).public_send("#{attribute}=", value)
    end
  end

  def initialize
    SCOPE_CLASSES.each do |scope_name, klass|
      instance_variable_set("@#{scope_name}", klass.new)
    end
    @additional_roles = {}
  end

  class << self
    def resolve_default_value(default_value)
      default_value.respond_to?(:call) ? default_value.call : (default_value.dup rescue default_value)
    end

    def config_boolean(method_name, default:)
      config = TurboChat.configuration
      value = config.respond_to?(method_name) ? config.public_send(method_name) : default
      ActiveModel::Type::Boolean.new.cast(value)
    rescue NoMethodError, TypeError
      default
    end
  end
end
