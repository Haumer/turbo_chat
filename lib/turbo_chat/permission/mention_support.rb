class TurboChat::Permission
  module MentionSupport
    def can_mention_members? = can_view_chat? && role_permission?(:mention_member)

    def can_mention_all? = can_view_chat? && role_permission?(:mention_all)

    def can_mention_roles? = can_view_chat? && role_permission?(:mention_role)

    def can_mention_token?(token)
      mention = token.to_s.strip
      return false if mention.blank?
      return false unless mention.start_with?("@")
      return can_mention_all? if mention.casecmp("@all").zero?
      return can_mention_roles? if ROLE_MENTION_TOKEN_PATTERN.match?(mention)
      return can_mention_members? if MEMBER_MENTION_TOKEN_PATTERN.match?(mention)

      false
    end
  end
end
