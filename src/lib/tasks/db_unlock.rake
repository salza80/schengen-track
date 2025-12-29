namespace :db do
  desc "Release any stale migration advisory locks"
  task unlock: :environment do
    connection = ActiveRecord::Base.connection
    
    if connection.adapter_name == 'PostgreSQL'
      puts "Checking for migration advisory locks..."
      
      # First, show ALL advisory locks
      all_locks_query = <<-SQL
        SELECT 
          locktype, 
          classid, 
          objid, 
          pid,
          state,
          query
        FROM pg_locks l
        LEFT JOIN pg_stat_activity a ON l.pid = a.pid
        WHERE locktype = 'advisory';
      SQL
      
      all_locks = connection.execute(all_locks_query)
      
      if all_locks.any?
        puts "Found #{all_locks.count} advisory lock(s) in database:"
        all_locks.each do |lock|
          puts "  - PID: #{lock['pid']}, State: #{lock['state']}, ClassID: #{lock['classid']}, ObjID: #{lock['objid']}"
        end
        
        # Try to terminate all advisory lock holders except ourselves
        terminate_query = <<-SQL
          SELECT 
            pid,
            pg_terminate_backend(pid) as terminated
          FROM pg_locks 
          WHERE locktype = 'advisory' 
            AND pid != pg_backend_pid();
        SQL
        
        terminated = connection.execute(terminate_query)
        if terminated.any?
          puts "✓ Terminated #{terminated.count} process(es) holding advisory locks"
        else
          puts "⚠ No processes to terminate (all locks are from current session)"
        end
      else
        puts "✓ No advisory locks found in database"
      end
      
      # Also try the nuclear option - cancel any long-running queries
      long_queries = <<-SQL
        SELECT 
          pid,
          now() - query_start AS duration,
          state,
          query,
          pg_cancel_backend(pid) as cancelled
        FROM pg_stat_activity
        WHERE state != 'idle'
          AND query LIKE '%db:migrate%'
          AND pid != pg_backend_pid()
          AND now() - query_start > interval '30 seconds';
      SQL
      
      cancelled = connection.execute(long_queries)
      if cancelled.any?
        puts "Cancelled #{cancelled.count} long-running migration queries"
      end
      
    else
      puts "Advisory lock clearing is only supported for PostgreSQL"
    end
  end
end
