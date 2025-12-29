class TasksController < ApplicationController
  before_action :authenticate_token, only: [:migrate, :create, :seed, :update_countries, :guest_cleanup, :unlock_migrations, :migrate_people_data, :fix_people_migration]
  before_action :check_deployment_window, only: [:migrate, :update_countries, :guest_cleanup, :unlock_migrations, :migrate_people_data, :fix_people_migration]
  
  # GET /tasks/fix_people_migration
  def fix_people_migration
    rake_fix = "db:fix_people_migration"
    output = `rake #{rake_fix} 2>&1`
    @success = $?.success?
    @output = output
    render_json_response_with_output
  end
  
  # GET /tasks/unlock_migrations
  def unlock_migrations
    rake_unlock = "db:unlock"
    output = `rake #{rake_unlock} 2>&1`
    @success = $?.success?
    @output = output
    render_json_response_with_output
  end
  
  # GET /tasks/migrations
  def migrate
    rake_migrate = "db:migrate"
    output = `rake #{rake_migrate} 2>&1`
    @success = $?.success?
    @output = output
    render_json_response_with_output
  end
  
  # GET /tasks/migrate_people_data
  def migrate_people_data
    batch_size = params[:batch_size] || '500'
    rake_migrate_people = "db:migrate_people_data BATCH_SIZE=#{batch_size}"
    output = `rake #{rake_migrate_people} 2>&1`
    @success = $?.success?
    
    # Read stats from temp file if available
    stats_file = '/tmp/people_migration_stats.json'
    if @success && File.exist?(stats_file)
      stats = JSON.parse(File.read(stats_file))
      File.delete(stats_file) # Clean up
      render json: { 
        success: @success, 
        total_users: stats['total_users'],
        migrated: stats['migrated'], 
        batches: stats['batches'],
        output: output
      }
    else
      @output = output
      render_json_response_with_output
    end
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

  def guest_cleanup
    max_batches = params[:max_batches]
    rake_guest_cleanup = "db:guest_cleanup"
    rake_guest_cleanup += "[,#{max_batches}]" if max_batches.present?
    @success = system("rake #{rake_guest_cleanup}")
    
    # Read stats from temp file if available
    stats_file = '/tmp/guest_cleanup_stats.json'
    if @success && File.exist?(stats_file)
      stats = JSON.parse(File.read(stats_file))
      File.delete(stats_file) # Clean up
      render json: { success: @success, deleted: stats['deleted'], batches: stats['batches'], remaining: stats['remaining'] }
    else
      render_json_response
    end
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

  def check_deployment_window
    unless deployment_in_progress?
      @success = false
      render json: { success: false, error: 'Deployment endpoints are only accessible within 1 hour of deployment' }, status: :forbidden
    end
  end

  def deployment_in_progress?
    return true if Rails.env.development?
    
    begin
      require 'aws-sdk-ssm'
      
      ssm_client = Aws::SSM::Client.new(region: ENV['AWS_REGION'] || 'us-east-1')
      param_name = '/schengen/deployment-timestamp'
      
      response = ssm_client.get_parameter(name: param_name)
      deployment_time = Time.parse(response.parameter.value)
      
      Time.now - deployment_time < 3600
    rescue Aws::SSM::Errors::ParameterNotFound
      Rails.logger.warn("Deployment timestamp parameter not found")
      false
    rescue => e
      Rails.logger.error("Error checking deployment window: #{e.message}")
      false
    end
  end

  def render_json_response
    render json: { success: @success }
  end

  def render_json_response_with_output
    response = { success: @success }
    response[:output] = @output if @output.present?
    render json: response
  end

  def render_json_response_unauthorized
    render json: { success: @success, error: 'Unauthorized' }, status: :unauthorized
  end
end
