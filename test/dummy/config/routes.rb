Rails.application.routes.draw do
  mount ChatGem::Engine => "/chat"
  root to: redirect("/chat")
end
