# frozen_string_literal: true

require 'json'
require 'rake'

module Lambda
  class TaskExecutor
    class << self
      def execute(event)
        command = (event['command'] || event['task'] || event['action']).to_s
        raise ArgumentError, 'command is required' if command.empty?

        case command
        when 'unlock_and_migrate'
          unlock_and_migrate
        when 'update_countries'
          run_rake('db:update_countries')
          { success: true }
        when 'guest_cleanup'
          guest_cleanup(event)
        when 'fix_people_migration'
          run_rake('db:fix_people_migration')
          { success: true }
        else
          raise ArgumentError, "Unsupported command: #{command}"
        end
      end

      private

      def unlock_and_migrate
        logs = []
        logs << terminate_connections
        run_rake('db:migrate')
        { success: true, logs: logs.compact }
      end

      def guest_cleanup(event)
        params = event['params'] || {}
        limit_date = params['limit_date']
        max_batches = params['max_batches']
        run_rake('db:guest_cleanup', limit_date, max_batches)
        stats_file = '/tmp/guest_cleanup_stats.json'

        stats = if File.exist?(stats_file)
          JSON.parse(File.read(stats_file))
        end

        File.delete(stats_file) if File.exist?(stats_file)
        payload = { success: true }
        payload[:stats] = stats if stats
        payload
      end

      def run_rake(task_name, *args)
        load_rake_tasks
        task = Rake::Task[task_name]
        task.reenable
        args.compact!
        task.invoke(*args)
      end

      def load_rake_tasks
        return if defined?(@tasks_loaded) && @tasks_loaded

        Rails.application.load_tasks
        @tasks_loaded = true
      end

      def terminate_connections
        connection = ActiveRecord::Base.connection
        return 'Non-PostgreSQL adapter, skipping connection termination' unless connection.adapter_name == 'PostgreSQL'

        sql = <<~SQL
          SELECT pg_terminate_backend(pid)
          FROM pg_stat_activity
          WHERE datname = current_database()
            AND pid != pg_backend_pid();
        SQL

        terminated = connection.execute(sql)
        "Terminated #{terminated.count} connection(s)"
      rescue => e
        "Failed to terminate connections: #{e.message}"
      end
    end
  end
end
