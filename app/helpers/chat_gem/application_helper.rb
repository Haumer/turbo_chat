module ChatGem
  module ApplicationHelper
    def chat_participant_name(participant)
      return "Unknown" if participant.nil?
      return participant.name if participant.respond_to?(:name)
      return participant.email if participant.respond_to?(:email)

      participant.to_s
    end
  end
end
