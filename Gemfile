source "https://rubygems.org"

gemspec

group :development, :test do
  gem "sqlite3", "~> 1.4"
  gem "minitest", "~> 5.27"
  gem "sprockets-rails", "~> 3.5"
  gem "ostruct"
end

group :development do
  gem "brakeman", require: false
  gem "bundler-audit", require: false
end

group :test do
  gem "capybara", "~> 3.40"
  gem "selenium-webdriver", "~> 4.29"
  gem "puma", "~> 6.4"
end
