class ApplicationController < ActionController::Base
  helper_method :chat_current_participant

  def chat_current_participant
    User.first || User.create!(email: "dummy@example.com")
  end
end
