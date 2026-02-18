require "rails/generators/base"

module ChatGem
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)
      desc "Installs ChatGem initializer and copies engine migrations"

      def copy_initializer
        template "chat_gem.rb", "config/initializers/chat_gem.rb"
      end

      def install_migrations
        rake "railties:install:migrations FROM=chat_gem"
      end
    end
  end
end
