class TasksController < ApplicationController
  before_action :authenticate_token, only: [:migrate, :create, :seed, :update_countries]
  # GET /tasks/migrations
  def migrate
    rake_migrate = "db:migrate"
    @success = system("rake #{rake_migrate}")
    render_json_response
  end
  def create
    rake_create = "db:create"
    @success = system("rake #{rake_create}")
    render_json_response
  end
  def seed
    rake_seed = "db:seed"
    @success = system("rake #{rake_seed}")
    render_json_response
  end
  def update_countries
    rake_update_countries = "db:update_countries"
    @success = system("rake #{rake_update_countries}")
    render_json_response
  end

  private 

  def authenticate_token
    token_param = params[:token]
    expected_token = ENV['TASK_PASSWORD']

    unless token_param && token_param == expected_token
      @success = false
      render_json_response_unauthorized
    end
  end

   def render_json_response
    render json: { success: @success }
  end

  def render_json_response_unauthorized
    render json: { success: @success, error: 'Unauthorized' }, status: :unauthorized
  end
end
