Rails.application.configure do
  config.cache_classes = true
  config.eager_load = false
  config.consider_all_requests_local = true
  config.action_controller.perform_caching = false
  config.cache_store = :null_store
  config.action_dispatch.show_exceptions = :none
  config.action_controller.allow_forgery_protection = false
  config.active_support.deprecation = :stderr
  # System tests use ephemeral localhost/127.0.0.1 hosts and ports.
  # Keep host authorization disabled in test only to avoid false negatives.
  config.hosts.clear
end
