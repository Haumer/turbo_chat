ENV["RAILS_ENV"] ||= "test"
require_relative "dummy/config/environment"
require "rails/test_help"
require "minitest/mock"

ActiveRecord::Migration.maintain_test_schema!

class ActiveSupport::TestCase
  parallelize(workers: 1)
end
