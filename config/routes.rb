ChatGem::Engine.routes.draw do
  root to: "chats#index"

  resources :chats, only: %i[index show new create] do
    member do
      patch :leave
      patch :close
      patch :reopen
    end

    resources :chat_memberships, only: :create
    resources :chat_messages, only: %i[index create update]
  end
end
