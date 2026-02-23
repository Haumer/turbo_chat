module TurboChat
  module ParticipantIdentity
    module_function

    def display_name(participant, unknown: "Unknown")
      return unknown if participant.nil?

      username(participant) || name(participant) || email(participant) || participant.to_s
    end

    def email(participant)
      return nil if participant.nil?
      return nil unless participant.respond_to?(:email)

      participant.email.to_s.presence
    end

    def mention_base_identifier(participant)
      return username(participant) if username(participant).present?

      email_value = email(participant)
      return email_value.to_s.split("@").first if email_value.present?
      return name(participant) if name(participant).present?

      participant.to_s
    end

    def username(participant)
      return nil if participant.nil?
      return nil unless participant.respond_to?(:username)

      participant.username.to_s.presence
    end

    def name(participant)
      return nil if participant.nil?
      return nil unless participant.respond_to?(:name)

      participant.name.to_s.presence
    end
  end
end
