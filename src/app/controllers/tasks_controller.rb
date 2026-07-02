require 'rake'
require 'securerandom'

class TasksController < ApplicationController
  before_action :authenticate_token, only: [:migrate, :create, :seed, :update_countries, :guest_cleanup, :unlock_migrations, :fix_people_migration, :unlock_and_migrate]
  before_action :check_deployment_window, only: [:migrate, :update_countries, :guest_cleanup, :unlock_migrations, :fix_people_migration, :unlock_and_migrate]
  
  # GET /tasks/fix_people_migration
  def fix_people_migration
    rake_fix = "db:fix_people_migration"
    output = `rake #{rake_fix} 2>&1`
    @success = $?.success?
    @output = output
    render_json_response_with_output
  end
  
  # GET /tasks/unlock_and_migrate
  # Combines unlock and migrate in a single Lambda invocation to avoid race conditions
  def unlock_and_migrate
    combined_output = []
    
    # Step 1: Quick unlock - just terminate other connections, no diagnostics
    combined_output << "=== Terminating stale connections ==="
    begin
      connection = ActiveRecord::Base.connection
      if connection.adapter_name == 'PostgreSQL'
        # Terminate ALL other connections to force release any locks
        terminate_query = <<-SQL
          SELECT pg_terminate_backend(pid)
          FROM pg_stat_activity
          WHERE datname = current_database()
            AND pid != pg_backend_pid();
        SQL
        terminated = connection.execute(terminate_query)
        combined_output << "Terminated #{terminated.count} connection(s)"
      end
    rescue => e
      combined_output << "Warning during unlock: #{e.message}"
    end
    
    # Step 2: Brief wait
    sleep 1
    
    # Step 3: Migrate
    combined_output << "\n=== Running migrations ==="
    rake_migrate = "db:migrate"
    migrate_output = `rake #{rake_migrate} 2>&1`
    combined_output << migrate_output
    migrate_success = $?.success?
    
    @success = migrate_success
    @output = combined_output.join("\n")
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
    stats_file = guest_cleanup_stats_file

    max_batches = parse_positive_integer_param(params[:max_batches])
    return render json: { success: false, error: 'max_batches must be a positive integer' }, status: :unprocessable_entity if params[:max_batches].present? && max_batches.nil?

    run_guest_cleanup_rake(max_batches, stats_file)

    raise "Guest cleanup completed without writing stats to #{stats_file}" unless File.exist?(stats_file)

    stats = JSON.parse(File.read(stats_file))
    render json: {
      success: true,
      deleted: stats['deleted'],
      batches: stats['batches'],
      remaining: stats['remaining'],
      expired_rate_limits_deleted: stats['expired_rate_limits_deleted']
    }
  rescue => e
    @success = false
    if e.message == 'Guest cleanup is already running'
      Rails.logger.warn("Guest cleanup skipped: #{e.message}")
      render json: { success: false, error: e.message }, status: :conflict
    else
      Rails.logger.error("Guest cleanup failed: #{e.class}: #{e.message}")
      render json: { success: false, error: e.message }, status: :internal_server_error
    end
  ensure
    File.delete(stats_file) if stats_file && File.exist?(stats_file)
  end

  private 

  def run_guest_cleanup_rake(max_batches, stats_file)
    Rails.application.load_tasks unless Rake::Task.task_defined?('db:guest_cleanup')
    task = Rake::Task['db:guest_cleanup']
    task.reenable
    task.invoke(nil, max_batches, stats_file)
  end

  def guest_cleanup_stats_file
    "/tmp/guest_cleanup_stats_#{SecureRandom.uuid}.json"
  end

  def parse_positive_integer_param(value)
    return nil if value.blank?

    integer = Integer(value, exception: false)
    integer if integer&.positive?
  end

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
