class TasksController < ApplicationController
  # GET /tasks/migrations
  def migrate
    rake_migrate = "db:migrate"
    system("rake #{rake_migrate}")
  end
   def create
    rake_create = "db:create"
    system("rake #{rake_create}")
  end
end
