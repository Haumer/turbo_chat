namespace :turbo_chat do
  namespace :install do
    desc "Install TurboChat migrations (alias for chat_gem:install:migrations)"
    task :migrations do
      task = Rake::Task["chat_gem:install:migrations"]
      task.reenable
      task.invoke
    end
  end
end
