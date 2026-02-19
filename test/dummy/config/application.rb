require_relative "boot"
require "rails/all"

Bundler.require(*Rails.groups)
require "turbo_chat"

module Dummy
  class Application < Rails::Application
    config.load_defaults 7.0
    config.eager_load = false
    config.secret_key_base = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
    config.hosts << "www.example.com"
    config.paths["db/migrate"] << TurboChat::Engine.root.join("db/migrate").to_s
  end
end
