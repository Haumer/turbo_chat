require_relative "lib/chat_gem/version"

Gem::Specification.new do |spec|
  spec.name        = "chat_gem"
  spec.version     = ChatGem::VERSION
  spec.authors     = ["ChatGem"]
  spec.email       = ["dev@example.com"]
  spec.homepage    = "https://example.com/chat_gem"
  spec.summary     = "Lightweight mountable chat engine for Rails"
  spec.description = "A mountable Rails engine with chats, messages, memberships, and Turbo Stream updates."
  spec.license     = "MIT"

  spec.files = Dir.chdir(__dir__) do
    Dir[
      "{app,config,db,lib}/**/*",
      "MIT-LICENSE",
      "README.md",
      "chat_gem.gemspec"
    ]
  end

  spec.required_ruby_version = ">= 3.1"

  spec.add_dependency "rails", ">= 7.0", "< 8.0"
  spec.add_dependency "turbo-rails", ">= 1.4", "< 3.0"

  spec.metadata["rubygems_mfa_required"] = "true"
end
