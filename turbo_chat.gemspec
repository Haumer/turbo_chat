require_relative "lib/turbo_chat/version"

Gem::Specification.new do |spec|
  spec.name        = "turbo_chat"
  spec.version     = TurboChat::VERSION
  spec.authors     = ["Alexander Haumer"]
  spec.homepage    = "https://github.com/Haumer/turbo_chat"
  spec.summary     = "Lightweight mountable chat engine for Rails"
  spec.description = "A mountable Rails engine with chats, messages, memberships, and Turbo Stream updates."
  spec.license     = "MIT"

  spec.files = Dir.chdir(__dir__) do
    Dir[
      "{app,config,db,lib}/**/*",
      "MIT-LICENSE",
      "README.md",
      "turbo_chat.gemspec"
    ]
  end

  spec.required_ruby_version = ">= 3.1"

  spec.add_dependency "rails", ">= 7.0", "< 8.0"
  spec.add_dependency "turbo-rails", ">= 1.4", "< 3.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "#{spec.homepage}/tree/main"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/README.md"
  spec.metadata["rubygems_mfa_required"] = "true"
end
