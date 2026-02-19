class ApplicationController < ActionController::Base
  helper_method :current_chat_participant

  def current_chat_participant
    User.first || User.create!(email: "dummy@example.com")
  end
end
