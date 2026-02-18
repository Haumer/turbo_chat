class User < ApplicationRecord
  acts_as_chat_participant

  validates :email, presence: true

  def to_s
    email
  end
end
