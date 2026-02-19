module TurboChat
  class Engine < ::Rails::Engine
    isolate_namespace TurboChat

    initializer "turbo_chat.helpers" do
      ActiveSupport.on_load(:action_controller_base) do
        helper TurboChat::ApplicationHelper
      end

      ActiveSupport.on_load(:action_view) do
        include TurboChat::ApplicationHelper
      end
    end

    initializer "turbo_chat.assets.precompile" do |app|
      next unless app.config.respond_to?(:assets)
      next unless app.config.assets.respond_to?(:precompile)

      app.config.assets.precompile += %w[
        turbo_chat/application.css
        turbo_chat/application.js
        turbo_chat/shared.js
        turbo_chat/messages.js
        turbo_chat/realtime.js
        turbo_chat/lifecycle_events.js
      ]
    end
  end
end
