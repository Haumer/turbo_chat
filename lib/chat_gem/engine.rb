module ChatGem
  class Engine < ::Rails::Engine
    isolate_namespace ChatGem

    initializer "chat_gem.helpers" do
      ActiveSupport.on_load(:action_controller_base) do
        helper ChatGem::ApplicationHelper
      end

      ActiveSupport.on_load(:action_view) do
        include ChatGem::ApplicationHelper
      end
    end

    initializer "chat_gem.assets.precompile" do |app|
      next unless app.config.respond_to?(:assets)
      next unless app.config.assets.respond_to?(:precompile)

      app.config.assets.precompile += %w[chat_gem/application.css chat_gem/application.js]
    end
  end
end
