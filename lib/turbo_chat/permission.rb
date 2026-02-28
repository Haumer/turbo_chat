require_relative "permission/support"
require_relative "permission/mention_support"

class TurboChat::Permission
  include Support
  include MentionSupport

  ROLE_MENTION_TOKEN_PATTERN = /\A@[A-Z][A-Z0-9_]{0,31}\z/.freeze
  MEMBER_MENTION_TOKEN_PATTERN = /\A@[a-z0-9_]{1,32}\z/i.freeze

  attr_reader :participant, :chat

  def initialize(participant, chat = nil)
    @participant = participant
    @chat = chat
  end

  def can_view_chat?
    return false unless participant_present?
    return true unless chat_present?

    actor_membership_active? && role_permission?(:view_chat)
  end

  def can_create_chat? = participant_present?

  def can_post_message?
    can_view_chat? &&
      !chat_input_disabled? &&
      role_permission?(:post_message) &&
      !chat_closed? &&
      !actor_membership_muted? &&
      !actor_membership_timed_out?
  end

  def can_mute_member?(target_membership = nil) = can_manage_target_membership?(:mute_member, target_membership)

  def can_timeout_member?(target_membership = nil) = can_manage_target_membership?(:timeout_member, target_membership)

  def can_ban_member?(target_membership = nil) = can_manage_target_membership?(:ban_member, target_membership)

  def can_invite_member? = can_view_chat? && role_permission?(:invite_member)

  def can_grant_member_permissions?(target_membership = nil) = can_manage_target_membership?(:grant_member_permissions, target_membership)

  def can_delete_message?(message = nil)
    return false unless can_view_chat? && role_permission?(:delete_message)
    return true if message.nil?
    return false unless message_in_chat?(message)

    can_act_on_target_membership?(membership_for(message.participant))
  end

  def can_edit_message?(message = nil)
    return false unless can_post_message?
    return true if message.nil?
    return false unless message_in_chat?(message)

    participant_type, participant_id = actor_identity
    return false if participant_type.blank? || participant_id.blank?

    message.participant_type.to_s == participant_type &&
      message.participant_id.to_s == participant_id.to_s
  end

  def can_close_chat? = can_view_chat? && role_permission?(:close_chat)

  def can_reopen_chat? = can_view_chat? && role_permission?(:reopen_chat)

  private

  def chat_input_disabled?
    configuration = TurboChat.configuration
    value = configuration.respond_to?(:disable_input) ? configuration.disable_input : false
    ActiveModel::Type::Boolean.new.cast(value)
  rescue StandardError
    false
  end
end
