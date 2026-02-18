module ChatGem
  module ApplicationHelper
    def chat_message_css_classes(chat_message:, own_message:)
      classes = ["chat-bubble"]
      classes << "chat-bubble--own" if own_message
      classes.concat(resolve_custom_message_css_classes(chat_message: chat_message, own_message: own_message))
      classes.uniq.join(" ")
    end

    def render_chat_message_body(chat_message)
      body = chat_message.body.to_s
      return content_tag(:p, body, class: "chat-body") unless ChatGem.configuration.render_message_html

      sanitized_html = sanitize(
        body,
        tags: Array(ChatGem.configuration.message_html_tags),
        attributes: Array(ChatGem.configuration.message_html_attributes)
      )
      content_tag(:div, sanitized_html, class: "chat-body")
    end

    def chat_participant_name(participant)
      return "Unknown" if participant.nil?
      return participant.name if participant.respond_to?(:name)
      return participant.email if participant.respond_to?(:email)

      participant.to_s
    end

    private

    def resolve_custom_message_css_classes(chat_message:, own_message:)
      resolver = ChatGem.configuration.message_css_class_resolver
      return [] unless resolver.respond_to?(:call)

      classes = case resolver.arity
      when 0
        resolver.call
      when 1
        resolver.call(chat_message)
      when 2
        resolver.call(chat_message, own_message)
      else
        resolver.call(chat_message, own_message, self)
      end

      Array(classes).flat_map { |value| value.to_s.split(/\s+/) }.reject(&:blank?)
    rescue ArgumentError
      []
    end
  end
end
