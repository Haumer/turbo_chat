ChatGem.configure do |config|
  config.permission_adapter = ChatGem::Permission
  config.max_chat_participants = 10
  config.max_message_length = 1000
  config.message_history_limit = 200
  config.show_timestamp = true
  config.show_role = false
  config.active_chat_window = 5.minutes
  config.emit_typing_events = false
  config.emit_message_events = false
  config.show_self_signals = false
  config.replace_signals_on_message_submit = false
  config.message_css_class_resolver = nil
  config.render_message_html = false
  config.message_html_tags = %w[a b br code em i li ol p pre strong ul]
  config.message_html_attributes = %w[href target rel class]
  config.timestamp_formatter = ->(timestamp, _chat_message) { I18n.l(timestamp.in_time_zone, format: :long) }
  config.role_formatter = ->(role, _chat_message) { role.to_s.humanize }
end
