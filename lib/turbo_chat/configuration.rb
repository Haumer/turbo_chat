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

  class ModeSettings
    class << self
      attr_reader :mode_attributes

      def configure_attributes(attributes)
        @mode_attributes = attributes
        attr_accessor(*attributes)
      end
    end

    configure_attributes(ATTRIBUTES)

    def initialize(defaults = {})
      self.class.mode_attributes.each do |attribute|
        instance_variable_set("@#{attribute}", nil)
      end

      defaults.each do |attribute, value|
        next unless respond_to?("#{attribute}=")

        public_send("#{attribute}=", TurboChat::Configuration.resolve_default_value(value))
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
    reset_modes!
  end

  def mode(name)
    normalized = self.class.normalize_mode_name(name)
    raise ArgumentError, "unknown chat mode: #{name.inspect}" if normalized.nil?

    @modes[normalized]
  end

  def reset_mode!(name)
    normalized = self.class.normalize_mode_name(name)
    raise ArgumentError, "unknown chat mode: #{name.inspect}" if normalized.nil?

    @modes[normalized] = ModeSettings.new(MODE_DEFAULTS.fetch(normalized))
  end

  def reset_modes!
    @modes = MODE_DEFAULTS.each_with_object({}) do |(mode_name, defaults), modes|
      modes[mode_name] = ModeSettings.new(defaults)
    end
  end

  def resolved_value(attribute, chat: nil, default: nil)
    base_value = if respond_to?(attribute)
                   public_send(attribute)
                 else
                   default
                 end

    mode_name = self.class.extract_chat_mode(chat)
    return base_value if mode_name.nil? || mode_name == :standard

    mode_settings = @modes[mode_name]
    return base_value unless mode_settings&.respond_to?(attribute)

    override_value = mode_settings.public_send(attribute)
    override_value.nil? ? base_value : override_value
  rescue NoMethodError, TypeError, ArgumentError
    default
  end

  class << self
    def resolve_default_value(default_value)
      default_value.respond_to?(:call) ? default_value.call : (default_value.dup rescue default_value)
    end

    def config_value(method_name, default: nil, chat: nil)
      config = TurboChat.configuration
      return config.resolved_value(method_name, chat: chat, default: default) if config.respond_to?(:resolved_value)
      return config.public_send(method_name) if config.respond_to?(method_name)

      default
    rescue NoMethodError, TypeError, ArgumentError
      default
    end

    def config_boolean(method_name, default:, chat: nil)
      value = config_value(method_name, default: default, chat: chat)
      ActiveModel::Type::Boolean.new.cast(value)
    rescue NoMethodError, TypeError
      default
    end

    def extract_chat_mode(chat_or_mode)
      case chat_or_mode
      when nil
        nil
      when String, Symbol
        normalize_mode_name(chat_or_mode)
      else
        return nil unless chat_or_mode.respond_to?(:chat_mode)

        normalize_mode_name(chat_or_mode.chat_mode)
      end
    end

    def normalize_mode_name(value)
      normalized = value.to_s.strip
      return nil if normalized.blank?

      mode_name = normalized.to_sym
      return nil unless MODE_NAMES.include?(mode_name)

      mode_name
    end
  end
end
