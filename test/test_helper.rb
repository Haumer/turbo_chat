ENV["RAILS_ENV"] ||= "test"
require_relative "dummy/config/environment"
require "rails/test_help"

ActiveRecord::Migration.maintain_test_schema!

class ActiveSupport::TestCase
  parallelize(workers: 1)
end
