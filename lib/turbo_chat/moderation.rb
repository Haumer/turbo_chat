require_relative "moderation/support"
require_relative "moderation/member_actions"
require_relative "moderation/chat_actions"

module TurboChat::Moderation
  class AuthorizationError < StandardError; end
  class InvalidActionError < StandardError; end

  extend MemberActions
  extend ChatActions
  extend Support
end
