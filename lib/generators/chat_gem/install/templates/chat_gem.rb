ChatGem.configure do |config|
  config.current_participant_method = :chat_current_participant
  config.current_participant_resolver = ->(value, _controller) { value }
  config.permission_adapter = ChatGem::Permission
  config.max_chat_participants = 10
  config.show_timestamp = true
  config.show_role = false
  config.active_chat_window = 5.minutes
  config.emit_typing_events = false
  config.emit_message_events = false
  config.timestamp_formatter = ->(timestamp, _chat_message) { I18n.l(timestamp.in_time_zone, format: :long) }
  config.role_formatter = ->(role, _chat_message) { role.to_s.humanize }
end
