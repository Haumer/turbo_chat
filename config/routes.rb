TurboChat::Engine.routes.draw do
  root to: "chats#index"

  resources :chats, only: %i[index show new create] do
    member do
      patch :accept
      patch :decline
      patch :leave
      patch :close
      patch :reopen
    end

    resources :chat_memberships, only: %i[create update] do
      member do
        patch :mute
        patch :ban
      end
    end
    resources :chat_messages, only: %i[index create update]
  end
end
