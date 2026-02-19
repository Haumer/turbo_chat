module ChatGem
  module ApplicationHelper
    HEX_COLOR_PATTERN = /\A#(?:\h{3}|\h{6}|\h{8})\z/.freeze
    EMOJI_ALIAS_PATTERN = /:([a-z0-9_+\-]{2,32}):/i.freeze
    MENTION_PATTERN = /(?<![[:alnum:]_])@[[:alpha:]][[:alnum:]_]{0,31}/.freeze

    include ChatGem::ApplicationHelper::ConfigSupport
    include ChatGem::ApplicationHelper::ParticipantSupport
    include ChatGem::ApplicationHelper::MessageRendering
    include ChatGem::ApplicationHelper::MentionSupport
  end
end
