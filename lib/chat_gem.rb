require "chat_gem/version"
require "chat_gem/configuration"
require "chat_gem/model_extensions/chat_participant"
require "chat_gem/permission"
require "chat_gem/moderation"
require "chat_gem/signals"
require "chat_gem/engine"

module ChatGem
  FALLBACK_ROLE_DEFINITIONS = {
    "member" => {
      name: "Member",
      rank: 0,
      permissions: %i[view_chat post_message]
    },
    "moderator" => {
      name: "Moderator",
      rank: 1,
      permissions: %i[view_chat post_message mute_member timeout_member ban_member delete_message]
    },
    "admin" => {
      name: "Admin",
      rank: 2,
      permissions: %i[view_chat post_message mute_member timeout_member ban_member delete_message close_chat reopen_chat]
    }
  }.freeze

  class << self
    def configuration
      @configuration ||= ChatGem::Configuration.new
    end

    def configure
      yield(configuration)
    end

    def configuration_value(key)
      config = configuration
      return config.public_send(key) if config.respond_to?(key)

      fallback_configuration_value(key)
    end

    def role_definition(key)
      config = configuration
      return config.role_definition(key) if config.respond_to?(:role_definition)

      role_definitions[key.to_s.strip]
    end

    def role_definitions
      config = configuration
      return config.role_definitions if config.respond_to?(:role_definitions)

      if ChatGem::Configuration.const_defined?(:DEFAULT_ROLE_DEFINITIONS)
        ChatGem::Configuration::DEFAULT_ROLE_DEFINITIONS
      else
        FALLBACK_ROLE_DEFINITIONS
      end
    end

    private

    def fallback_configuration_value(key)
      case key.to_sym
      when :current_participant_method
        :chat_current_participant
      when :current_participant_resolver
        lambda { |participant, _controller = nil|
          participant
        }
      when :permission_adapter
        ChatGem::Permission
      when :max_chat_participants
        10
      when :show_timestamp
        true
      when :show_role
        false
      when :active_chat_window
        5.minutes
      when :emit_typing_events, :emit_message_events
        false
      when :timestamp_formatter
        lambda { |timestamp, _chat_message = nil|
          I18n.l(timestamp.in_time_zone, format: :long)
        }
      when :role_formatter
        lambda { |role, _chat_message = nil|
          role.to_s.humanize
        }
      end
    end
  end

  def self.table_name_prefix
    "chat_gem_"
  end
end
