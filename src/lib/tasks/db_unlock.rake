namespace :db do
  desc "Release any stale migration advisory locks"
  task unlock: :environment do
    connection = ActiveRecord::Base.connection
    
    if connection.adapter_name == 'PostgreSQL'
      puts "Checking for migration advisory locks..."
      
      # Calculate the lock key Rails uses
      db_name = connection.current_database
      require 'zlib'
      lock_id = Zlib.crc32(db_name)
      
      puts "Database: #{db_name}, Lock ID: #{lock_id}"
      
      # Find processes holding THIS specific lock
      specific_lock_query = <<-SQL
        SELECT 
          l.pid,
          a.state,
          a.query,
          now() - a.state_change AS duration,
          pg_terminate_backend(l.pid) as terminated
        FROM pg_locks l
        LEFT JOIN pg_stat_activity a ON l.pid = a.pid
        WHERE l.locktype = 'advisory' 
          AND l.objid = #{lock_id}
          AND l.pid != pg_backend_pid();
      SQL
      
      terminated = connection.execute(specific_lock_query)
      
      if terminated.any?
        puts "Found and terminated #{terminated.count} process(es) holding migration lock:"
        terminated.each do |proc|
          puts "  - PID: #{proc['pid']}, State: #{proc['state']}, Duration: #{proc['duration']}"
        end
        puts "✓ Migration lock released"
      else
        puts "No processes found holding the migration lock"
        
        # Show ALL advisory locks for debugging
        all_locks_query = <<-SQL
          SELECT 
            l.locktype, 
            l.classid, 
            l.objid, 
            l.pid,
            a.state
          FROM pg_locks l
          LEFT JOIN pg_stat_activity a ON l.pid = a.pid
          WHERE l.locktype = 'advisory';
        SQL
        
        all_locks = connection.execute(all_locks_query)
        if all_locks.any?
          puts "\nAll advisory locks in database:"
          all_locks.each do |lock|
            puts "  - PID: #{lock['pid']}, ObjID: #{lock['objid']}, State: #{lock['state']}"
          end
        end
      end
      
      # Also terminate any idle-in-transaction connections
      idle_in_transaction = <<-SQL
        SELECT 
          pid,
          now() - state_change AS duration,
          state,
          pg_terminate_backend(pid) as terminated
        FROM pg_stat_activity
        WHERE state = 'idle in transaction'
          AND pid != pg_backend_pid()
          AND now() - state_change > interval '2 minutes';
      SQL
      
      terminated_idle = connection.execute(idle_in_transaction)
      if terminated_idle.any?
        puts "\nTerminated #{terminated_idle.count} idle-in-transaction connections"
      end
      
    else
      puts "Advisory lock clearing is only supported for PostgreSQL"
    end
  end
end
