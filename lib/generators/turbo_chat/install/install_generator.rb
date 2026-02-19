require "rails/generators/base"

module TurboChat
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)
      desc "Installs TurboChat initializer and copies engine migrations"

      def copy_initializer
        template "turbo_chat.rb", "config/initializers/turbo_chat.rb"
      end

      def install_migrations
        rake "railties:install:migrations FROM=chat_gem"
      end
    end
  end
end
