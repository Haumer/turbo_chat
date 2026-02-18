ChatGem::Engine.routes.draw do
  root to: "chats#index"

  resources :chats, only: %i[index show new create] do
    resources :chat_messages, only: %i[index create]
  end
end
