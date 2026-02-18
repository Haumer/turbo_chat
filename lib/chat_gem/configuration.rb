module ChatGem
  class Configuration
    DEFAULT_ROLE_DEFINITIONS = {
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

    attr_accessor :current_participant_method,
                  :current_participant_resolver,
                  :permission_adapter,
                  :max_chat_participants,
                  :show_timestamp,
                  :show_role,
                  :active_chat_window,
                  :emit_typing_events,
                  :emit_message_events,
                  :timestamp_formatter,
                  :role_formatter

    def initialize
      @current_participant_method = :chat_current_participant
      @current_participant_resolver = lambda { |participant, _controller = nil|
        participant
      }
      @permission_adapter = ChatGem::Permission
      @max_chat_participants = 10
      @show_timestamp = true
      @show_role = false
      @active_chat_window = 5.minutes
      @emit_typing_events = false
      @emit_message_events = false
      @additional_roles = {}
      @timestamp_formatter = lambda { |timestamp, _chat_message = nil|
        I18n.l(timestamp.in_time_zone, format: :long)
      }
      @role_formatter = lambda { |role, _chat_message = nil|
        role.to_s.humanize
      }
    end

    def add_role(key, name:, permissions:, rank: 0)
      normalized_key = normalize_role_key(key)
      raise ArgumentError, "Role key cannot be blank" if normalized_key.blank?
      raise ArgumentError, "Role #{normalized_key} is reserved" if DEFAULT_ROLE_DEFINITIONS.key?(normalized_key)

      role_name = name.to_s.strip
      raise ArgumentError, "Role name cannot be blank" if role_name.blank?

      @additional_roles[normalized_key] = {
        name: role_name,
        rank: rank.to_i,
        permissions: Array(permissions).map { |permission| permission.to_sym }.uniq
      }
    end

    def remove_role(key)
      @additional_roles.delete(normalize_role_key(key))
    end

    def clear_additional_roles!
      @additional_roles = {}
    end

    def additional_roles
      @additional_roles.dup
    end

    def role_definitions
      DEFAULT_ROLE_DEFINITIONS.merge(@additional_roles)
    end

    def role_definition(key)
      role_definitions[normalize_role_key(key)]
    end

    private

    def normalize_role_key(key)
      key.to_s.strip
    end
  end
end
