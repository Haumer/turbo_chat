module ChatGem
  module ApplicationHelper
    HEX_COLOR_PATTERN = /\A#(?:\h{3}|\h{6}|\h{8})\z/.freeze
    EMOJI_ALIAS_PATTERN = /:([a-z0-9_+\-]{2,32}):/i.freeze
    MENTION_PATTERN = /(?<![[:alnum:]_])@[[:alpha:]][[:alnum:]_]{0,31}/.freeze

    def chat_message_css_classes(chat_message:, own_message:)
      classes = ["chat-bubble"]
      classes << "chat-bubble--own" if own_message
      classes.concat(resolve_custom_message_css_classes(chat_message: chat_message, own_message: own_message))
      classes.uniq.join(" ")
    end

    def chat_message_inline_style(chat_message:, own_message:)
      hex_color = resolve_message_hex_color(chat_message: chat_message, own_message: own_message)
      return nil if hex_color.blank?

      "--chat-bubble-bg: #{hex_color}; --chat-bubble-border: #{hex_color};"
    end

    def chat_mentions_container_inline_style
      hex_color = normalize_hex_color(chat_config_value(:mention_mark_hex_color))
      hex_color ||= normalize_hex_color(chat_config_value(:mention_highlight_hex_color))
      return nil if hex_color.blank?

      mention_mark_background = hex_color_with_alpha(hex_color, alpha: 0.22)
      "--chat-mention-highlight-color: #{hex_color}; --chat-mention-mark-background: #{mention_mark_background};"
    end

    def render_chat_message_body(chat_message)
      body = chat_message.body.to_s
      return content_tag(:p, decorate_plain_message_text(body).html_safe, class: "chat-body") unless ChatGem.configuration.render_message_html

      sanitized_html = sanitize(
        body,
        tags: Array(ChatGem.configuration.message_html_tags),
        attributes: Array(ChatGem.configuration.message_html_attributes)
      )
      content_tag(:div, sanitized_html, class: "chat-body")
    end

    def chat_participant_name(participant)
      return "Unknown" if participant.nil?
      return participant.username if participant.respond_to?(:username) && participant.username.present?
      return participant.name if participant.respond_to?(:name) && participant.name.present?
      return participant.email if participant.respond_to?(:email) && participant.email.present?

      participant.to_s
    end

    def chat_message_mention_tokens(chat_message)
      return [] unless ChatGem.configuration.enable_mentions
      return [] if chat_message.nil?

      chat_message.body.to_s.scan(MENTION_PATTERN).uniq
    end

    def chat_mention_options(chat:, permission: nil)
      mention_permission = permission || mention_permission_for(chat)
      allow_member_mentions = mention_permission.nil? ? true : mention_permission_allows?(mention_permission, :can_mention_members?)
      allow_all_mentions = mention_permission.nil? ? true : mention_permission_allows?(mention_permission, :can_mention_all?)
      allow_role_mentions = mention_permission.nil? ? true : mention_permission_allows?(mention_permission, :can_mention_roles?)
      allow_role_mentions &&= !chat_mention_filter_hide_roles?
      exclude_self_mentions = chat_mention_filter_exclude_self?
      viewer_participant = mention_viewer_participant(permission: mention_permission)

      options = []
      options << { token: "@all", label: "All members", kind: "group" } if allow_all_mentions
      return options unless chat.respond_to?(:chat_memberships)

      if allow_member_mentions
        chat_member_mention_entries(chat).each do |entry|
          next if exclude_self_mentions && same_chat_participant?(entry[:participant], viewer_participant)

          options << {
            token: entry[:token],
            label: entry[:label],
            kind: "member",
            participant_type: entry[:participant_type],
            participant_id: entry[:participant_id]
          }
        end
      end

      if allow_role_mentions
        options.concat(chat_role_mention_entries(chat))
      end

      options
    end

    def chat_mention_filter_exclude_self?
      chat_config_boolean(:mention_filter_exclude_self, default: true)
    end

    def chat_mention_filter_hide_roles?
      chat_config_boolean(:mention_filter_hide_roles, default: true)
    end

    def chat_emit_mention_events?
      chat_config_boolean(:emit_mention_events, default: false)
    end

    def chat_emit_invitation_events?
      chat_config_boolean(:emit_invitation_events, default: false)
    end

    def chat_self_mention_tokens(chat:, participant: nil)
      viewer = participant || current_chat_participant_for_view
      return [] if viewer.nil?
      return [] unless chat.respond_to?(:chat_memberships)

      chat_member_mention_entries(chat).each_with_object([]) do |entry, tokens|
        next unless same_chat_participant?(entry[:participant], viewer)

        tokens << entry[:token]
      end
    end

    def chat_self_role_mention_token(chat:, participant: nil)
      viewer = participant || current_chat_participant_for_view
      return nil if viewer.nil?
      return nil unless chat.respond_to?(:chat_memberships)

      membership = chat.chat_memberships.active.find_by(participant: viewer)
      return nil if membership.nil?

      role_key = membership.effective_role_key.to_s.strip
      return nil if role_key.blank?

      "@#{role_key.upcase}"
    end

    def chat_mentions_enabled_for?(chat:, permission: nil)
      return false unless ChatGem.configuration.enable_mentions

      mention_permission = permission || mention_permission_for(chat)
      return true if mention_permission.nil?

      mention_permission_allows?(mention_permission, :can_mention_members?) ||
        mention_permission_allows?(mention_permission, :can_mention_all?) ||
        mention_permission_allows?(mention_permission, :can_mention_roles?)
    end

    def own_chat_message?(chat_message, participant: nil)
      return false if chat_message.nil?

      participant ||= current_chat_participant_for_view
      return false if participant.nil?

      participant_type = participant.class.base_class.name
      participant_id = participant.id
      return false if participant_type.blank? || participant_id.blank?

      chat_message.participant_type.to_s == participant_type &&
        chat_message.participant_id.to_s == participant_id.to_s
    end

    def can_edit_chat_message?(chat_message, participant: nil)
      return false if chat_message.nil?

      participant ||= current_chat_participant_for_view
      if participant.nil?
        return true unless respond_to?(:current_chat_participant, true)

        return false
      end

      adapter = ChatGem.configuration.permission_adapter
      return false unless adapter.respond_to?(:new)

      permission = adapter.new(participant, chat_message.chat)
      if permission.respond_to?(:can_edit_message?)
        return permission.can_edit_message?(chat_message)
      end

      return false if permission.respond_to?(:can_post_message?) && !permission.can_post_message?

      own_chat_message?(chat_message, participant: participant)
    rescue StandardError
      false
    end

    private

    def current_chat_participant_for_view
      return nil unless respond_to?(:current_chat_participant, true)

      current_chat_participant
    rescue StandardError
      nil
    end

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

    def resolve_message_hex_color(chat_message:, own_message:)
      role_color = resolve_role_message_hex_color(chat_message: chat_message, own_message: own_message)
      return role_color if role_color.present?

      base_color = own_message ? ChatGem.configuration.own_message_hex_color : ChatGem.configuration.other_message_hex_color
      normalize_hex_color(base_color)
    end

    def resolve_role_message_hex_color(chat_message:, own_message:)
      role_colors = ChatGem.configuration.role_message_hex_colors
      return nil unless role_colors.is_a?(Hash)

      role_key = chat_message_role_key(chat_message)
      return nil if role_key.blank?

      role_config = role_colors[role_key] || role_colors[role_key.to_sym]
      return normalize_hex_color(role_config) unless role_config.is_a?(Hash)

      variant = if own_message
                  role_config[:own] || role_config["own"]
                else
                  role_config[:other] || role_config["other"]
                end

      variant ||= role_config[:default] || role_config["default"]
      normalize_hex_color(variant)
    end

    def chat_message_role_key(chat_message)
      return nil unless chat_message.respond_to?(:participant_membership_role)

      chat_message.participant_membership_role.to_s.strip.presence
    end

    def normalize_hex_color(value)
      candidate = value.to_s.strip
      return nil if candidate.blank?

      candidate = "##{candidate}" unless candidate.start_with?("#")
      return nil unless HEX_COLOR_PATTERN.match?(candidate)

      candidate.downcase
    end

    def hex_color_with_alpha(hex_color, alpha:)
      normalized_hex = normalize_hex_color(hex_color)
      return nil if normalized_hex.blank?

      red, green, blue = case normalized_hex.length
                         when 4
                           [
                             normalized_hex[1] * 2,
                             normalized_hex[2] * 2,
                             normalized_hex[3] * 2
                           ]
                         when 7, 9
                           [
                             normalized_hex[1, 2],
                             normalized_hex[3, 2],
                             normalized_hex[5, 2]
                           ]
                         else
                           return nil
                         end

      alpha_value = alpha.to_f
      alpha_value = 0.0 if alpha_value.negative?
      alpha_value = 1.0 if alpha_value > 1.0

      alpha_hex = (alpha_value * 255).round.to_s(16).rjust(2, "0")
      "##{red}#{green}#{blue}#{alpha_hex}".downcase
    end

    def decorate_plain_message_text(body)
      formatted = ERB::Util.html_escape(body.to_s)
      formatted = apply_emoji_aliases(formatted) if ChatGem.configuration.enable_emoji_aliases
      formatted = apply_mention_highlights(formatted) if ChatGem.configuration.enable_mentions
      formatted.gsub(/\r\n?|\n/, "<br>")
    end

    def apply_emoji_aliases(text)
      emoji_aliases = ChatGem.configuration.effective_emoji_aliases
      return text if emoji_aliases.empty?

      text.gsub(EMOJI_ALIAS_PATTERN) do |match|
        alias_key = Regexp.last_match(1).to_s.downcase
        emoji_aliases.fetch(alias_key, match)
      end
    end

    def apply_mention_highlights(text)
      text.gsub(MENTION_PATTERN) do |mention|
        %(<span class="chat-mention">#{mention}</span>)
      end
    end

    def participant_mention_base_identifier(participant)
      return participant.username if participant.respond_to?(:username) && participant.username.present?
      if participant.respond_to?(:email) && participant.email.present?
        return participant.email.to_s.split("@").first
      end
      return participant.name if participant.respond_to?(:name) && participant.name.present?

      participant.to_s
    end

    def fallback_mention_identifier(participant)
      participant_id = participant.respond_to?(:id) ? participant.id : nil
      return "member_#{participant_id}" if participant_id.present?

      "member"
    end

    def normalized_mention_identifier(value)
      slug = I18n.transliterate(value.to_s)
      slug = slug.downcase.gsub(/[^a-z0-9_]+/, "_").gsub(/\A_+|_+\z/, "").squeeze("_")
      slug = "member_#{slug}" if slug.match?(/\A\d/)
      slug.presence
    end

    def unique_mention_token(identifier, taken_tokens)
      base = normalized_mention_identifier(identifier) || "member"
      token = "@#{base}"
      return taken_tokens[token] = token unless taken_tokens.key?(token)

      suffix = 2
      loop do
        candidate = "@#{base}_#{suffix}"
        unless taken_tokens.key?(candidate)
          taken_tokens[candidate] = candidate
          return candidate
        end
        suffix += 1
      end
    end

    def chat_member_mention_entries(chat)
      taken_tokens = {}

      active_chat_memberships(chat).each_with_object([]) do |membership, entries|
        participant = membership.participant
        next if participant.nil?

        identifier = normalized_mention_identifier(participant_mention_base_identifier(participant))
        identifier = fallback_mention_identifier(participant) if identifier.blank?
        token = unique_mention_token(identifier, taken_tokens)

        entries << {
          token: token,
          label: chat_participant_name(participant),
          participant: participant,
          participant_type: participant.class.base_class.name,
          participant_id: participant.id
        }
      end
    end

    def chat_role_mention_entries(chat)
      role_tokens = {}

      active_chat_memberships(chat).each_with_object([]) do |membership, entries|
        role_key = membership.effective_role_key.to_s.strip
        next if role_key.blank?

        role_token = "@#{role_key.upcase}"
        next if role_tokens[role_token]

        role_tokens[role_token] = true
        entries << {
          token: role_token,
          label: "#{membership.effective_role_name} role",
          kind: "role"
        }
      end
    end

    def active_chat_memberships(chat)
      return [] unless chat.respond_to?(:chat_memberships)

      chat.chat_memberships.active.includes(:participant).order(:id)
    end

    def mention_viewer_participant(permission:)
      return permission.participant if permission.respond_to?(:participant) && permission.participant.present?

      current_chat_participant_for_view
    end

    def same_chat_participant?(first, second)
      return false if first.nil? || second.nil?
      return false unless first.respond_to?(:id) && second.respond_to?(:id)

      first_type = first.class.base_class.name
      second_type = second.class.base_class.name
      return false if first_type.blank? || second_type.blank?
      return false if first.id.blank? || second.id.blank?

      first_type == second_type && first.id.to_s == second.id.to_s
    end

    def mention_permission_for(chat)
      return nil unless respond_to?(:current_chat_participant, true)

      participant = current_chat_participant
      return nil if participant.nil?

      ChatGem.configuration.permission_adapter.new(participant, chat)
    rescue StandardError
      nil
    end

    def mention_permission_allows?(permission, method_name)
      return true unless permission.respond_to?(method_name)

      permission.public_send(method_name)
    rescue StandardError
      false
    end

    def chat_config_value(method_name, default: nil)
      configuration = ChatGem.configuration
      return default unless configuration.respond_to?(method_name)

      configuration.public_send(method_name)
    rescue StandardError
      default
    end

    def chat_config_boolean(method_name, default:)
      value = chat_config_value(method_name, default: default)
      ActiveModel::Type::Boolean.new.cast(value)
    end
  end
end
