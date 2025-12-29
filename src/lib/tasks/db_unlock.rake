namespace :db do
  desc "Release any stale migration advisory locks"
  task unlock: :environment do
    connection = ActiveRecord::Base.connection
    
    if connection.adapter_name == 'PostgreSQL'
      puts "Checking for migration advisory locks..."
      
      # First, show ALL advisory locks
      all_locks_query = <<-SQL
        SELECT 
          l.locktype, 
          l.classid, 
          l.objid, 
          l.pid,
          a.state,
          a.query
        FROM pg_locks l
        LEFT JOIN pg_stat_activity a ON l.pid = a.pid
        WHERE l.locktype = 'advisory';
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
            l.pid,
            pg_terminate_backend(l.pid) as terminated
          FROM pg_locks l
          WHERE l.locktype = 'advisory' 
            AND l.pid != pg_backend_pid();
        SQL
        
        terminated = connection.execute(terminate_query)
        if terminated.any?
          puts "✓ Terminated #{terminated.count} process(es) holding advisory locks"
        end
      else
        puts "No advisory locks visible in current query"
      end
      
      # Force unlock the specific Rails migration lock
      # Rails uses a lock based on a hash of the database name
      # We'll try to unlock it even if we don't see it
      puts "\nAttempting to force-unlock Rails migration lock..."
      
      # Calculate the lock key Rails uses (based on ActiveRecord code)
      db_name = connection.current_database
      # Rails uses Zlib.crc32 on the database name
      require 'zlib'
      lock_id = Zlib.crc32(db_name)
      
      puts "Database: #{db_name}, Lock ID: #{lock_id}"
      
      # Try to unlock it (won't error if not locked)
      begin
        connection.execute("SELECT pg_advisory_unlock(#{lock_id})")
        puts "✓ Attempted to unlock migration lock #{lock_id}"
      rescue => e
        puts "Note: #{e.message}"
      end
      
      # Also terminate any connections that are idle in transaction for too long
      idle_in_transaction = <<-SQL
        SELECT 
          pid,
          now() - state_change AS duration,
          state,
          pg_terminate_backend(pid) as terminated
        FROM pg_stat_activity
        WHERE state = 'idle in transaction'
          AND pid != pg_backend_pid()
          AND now() - state_change > interval '5 minutes';
      SQL
      
      terminated_idle = connection.execute(idle_in_transaction)
      if terminated_idle.any?
        puts "Terminated #{terminated_idle.count} idle-in-transaction connections"
      end
      
    else
      puts "Advisory lock clearing is only supported for PostgreSQL"
    end
  end
end
