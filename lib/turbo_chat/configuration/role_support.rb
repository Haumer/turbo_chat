class TurboChat::Configuration
  module RoleSupport
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

    def remove_role(key) = @additional_roles.delete(normalize_role_key(key))

    def clear_additional_roles! = @additional_roles = {}

    def additional_roles = @additional_roles.dup

    def role_definitions = DEFAULT_ROLE_DEFINITIONS.merge(@additional_roles)

    def role_definition(key) = role_definitions[normalize_role_key(key)]

    private

    def normalize_role_key(key) = key.to_s.strip
  end
end
