Rails.application.routes.draw do
  mount TurboChat::Engine => "/chat"
  root to: redirect("/chat")
end
