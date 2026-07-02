# frozen_string_literal: true

require 'json'
require 'rake'
require 'securerandom'

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
        logs = with_database_timeouts do
          with_migration_retries do |attempt|
            attempt_logs = []
            log_task_message("Starting database unlock before migrations (attempt #{attempt})")
            configure_database_timeouts
            attempt_logs << log_database_activity

            if attempt == 1
              unlock_log = terminate_connections
              attempt_logs << unlock_log
              log_task_message(unlock_log) if unlock_log
            else
              skip_log = "Skipping connection termination on migration retry #{attempt}"
              attempt_logs << skip_log
              log_task_message(skip_log)
            end

            log_task_message("Starting database migrations (attempt #{attempt})")
            run_rake('db:migrate')
            log_task_message("Database migrations completed (attempt #{attempt})")
            attempt_logs
          end
        end
        { success: true, logs: logs.compact }
      end

      def guest_cleanup(event)
        params = event['params'] || {}
        limit_date = params['limit_date']
        max_batches = params['max_batches']
        stats_file = guest_cleanup_stats_file

        run_rake('db:guest_cleanup', limit_date, max_batches, stats_file)

        raise "Guest cleanup completed without writing stats to #{stats_file}" unless File.exist?(stats_file)

        stats = JSON.parse(File.read(stats_file))
        { success: true, stats: stats }
      ensure
        File.delete(stats_file) if stats_file && File.exist?(stats_file)
      end

      def run_rake(task_name, *args)
        load_rake_tasks
        task = Rake::Task[task_name]
        task.reenable
        args.pop while args.last.nil?
        task.invoke(*args)
      end

      def guest_cleanup_stats_file
        "/tmp/guest_cleanup_stats_#{SecureRandom.uuid}.json"
      end

      def load_rake_tasks
        return if defined?(@tasks_loaded) && @tasks_loaded

        Rails.application.load_tasks
        @tasks_loaded = true
      end

      def log_task_message(message)
        Rails.logger.info(message)
        puts(message)
      end

      def with_database_timeouts
        yield
      ensure
        reset_database_timeouts
        ActiveRecord::Base.clear_active_connections!
      end

      def with_migration_retries
        logs = []
        attempts = 3

        (1..attempts).each do |attempt|
          return logs.concat(yield(attempt))
        rescue => e
          raise unless retryable_migration_error?(e)

          logs << "Migration attempt #{attempt} failed: #{e.class}: #{e.message}"
          log_task_message(logs.last)
          raise if attempt == attempts

          sleep_seconds = attempt * 5
          log_task_message("Retrying database migrations in #{sleep_seconds} seconds")
          sleep sleep_seconds
          ActiveRecord::Base.clear_active_connections!
        end
      end

      def configure_database_timeouts
        connection = ActiveRecord::Base.connection
        return unless connection.adapter_name == 'PostgreSQL'

        connection.execute("SET lock_timeout = '10s'")
        connection.execute("SET statement_timeout = '120s'")
        log_task_message('Configured migration lock_timeout=10s and statement_timeout=120s')
      end

      def reset_database_timeouts
        return unless ActiveRecord::Base.connected?

        connection = ActiveRecord::Base.connection
        return unless connection.adapter_name == 'PostgreSQL'

        connection.execute('RESET lock_timeout')
        connection.execute('RESET statement_timeout')
        log_task_message('Reset migration database timeouts')
      rescue => e
        log_task_message("Failed to reset migration database timeouts: #{e.class}: #{e.message}")
      end

      def retryable_migration_error?(error)
        current_error = error

        while current_error
          return true if retryable_migration_error_class_name?(current_error.class.name)
          return true if retryable_statement_error_message?(current_error.message)

          current_error = current_error.respond_to?(:cause) ? current_error.cause : nil
        end

        false
      end

      def retryable_migration_error_class_name?(class_name)
        [
          'ActiveRecord::LockWaitTimeout',
          'ActiveRecord::QueryCanceled',
          'ActiveRecord::ConnectionNotEstablished',
          'ActiveRecord::ConnectionTimeoutError',
          'PG::ConnectionBad'
        ].include?(class_name)
      end

      def retryable_statement_error_message?(message)
        message.to_s.match?(/lock timeout|statement timeout|canceling statement due to statement timeout|server closed the connection|connection.*timed out/i)
      end

      def log_database_activity
        connection = ActiveRecord::Base.connection
        return 'Non-PostgreSQL adapter, skipping database activity diagnostics' unless connection.adapter_name == 'PostgreSQL'

        rows = connection.exec_query(<<~SQL)
          SELECT state, wait_event_type, wait_event, count(*) AS count
          FROM pg_stat_activity
          WHERE datname = current_database()
          GROUP BY state, wait_event_type, wait_event
          ORDER BY count DESC
        SQL
        message = "Database activity before migration: #{rows.to_a.inspect}"
        log_task_message(message)
        message
      rescue => e
        message = "Failed to collect database activity: #{e.class}: #{e.message}"
        log_task_message(message)
        message
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
