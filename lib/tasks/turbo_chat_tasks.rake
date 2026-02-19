namespace :turbo_chat do
  namespace :install do
    desc "Install TurboChat migrations"
    task :migrations do
      previous_from = ENV["FROM"]
      ENV["FROM"] = "turbo_chat"
      task = Rake::Task["railties:install:migrations"]
      task.reenable
      task.invoke
    ensure
      ENV["FROM"] = previous_from
    end
  end
end
