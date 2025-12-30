namespace :db do
  desc "Release any stale migration advisory locks"
  task unlock: :environment do
    connection = ActiveRecord::Base.connection
    
    if connection.adapter_name == 'PostgreSQL'
      puts "Checking for migration advisory locks..."
      
      # Calculate the lock key Rails uses (must match Rails' calculation)
      db_name = connection.current_database
      require 'zlib'
      migrator_salt = 2053462845 # ActiveRecord::Migrator::MIGRATOR_SALT
      db_name_hash = Zlib.crc32(db_name)
      lock_id = migrator_salt * db_name_hash
      
      puts "Database: #{db_name}"
      puts "Lock ID: #{lock_id}"
      
      # Find ALL advisory locks in the database
      all_locks_query = <<-SQL
        SELECT 
          l.pid,
          l.objid,
          l.granted,
          a.state,
          a.application_name,
          now() - a.state_change AS duration
        FROM pg_locks l
        LEFT JOIN pg_stat_activity a ON l.pid = a.pid
        WHERE l.locktype = 'advisory'
        ORDER BY l.objid;
      SQL
      
      all_locks = connection.execute(all_locks_query)
      
      if all_locks.any?
        puts "\nAll advisory locks currently in database:"
        all_locks.each do |lock|
          marker = lock['objid'].to_i == lock_id ? " ← MIGRATION LOCK" : ""
          puts "  - PID: #{lock['pid']}, ObjID: #{lock['objid']}, State: #{lock['state']}, App: #{lock['application_name']}#{marker}"
        end
      else
        puts "\nNo advisory locks found in database"
      end
      
      # Strategy 1: Try to unlock from every session that might have it
      # Query all connections and try to unlock from each one
      puts "\nAttempting to release lock from all sessions..."
      all_sessions_query = <<-SQL
        SELECT DISTINCT pid
        FROM pg_stat_activity
        WHERE datname = current_database()
          AND pid != pg_backend_pid();
      SQL
      
      sessions = connection.execute(all_sessions_query)
      puts "Found #{sessions.count} other session(s)"
      
      # Strategy 2: Terminate ALL other connections to force release of locks
      # This is necessary because pg_advisory_unlock only works from the session that acquired the lock
      puts "\nTerminating all other database connections..."
      terminate_all = <<-SQL
        SELECT 
          pid,
          state,
          application_name,
          usename,
          pg_terminate_backend(pid) as terminated
        FROM pg_stat_activity
        WHERE datname = current_database()
          AND pid != pg_backend_pid();
      SQL
      
      terminated_all = connection.execute(terminate_all)
      if terminated_all.any?
        puts "✓ Terminated #{terminated_all.count} connection(s)"
        terminated_all.each do |proc|
          puts "  - PID: #{proc['pid']}, User: #{proc['usename']}, State: #{proc['state']}, App: #{proc['application_name']}"
        end
      else
        puts "No other connections found to terminate"
      end
      
      # Give PostgreSQL a moment to clean up
      sleep 1
      
      # Strategy 3: Use our connection to try to acquire and immediately release the lock
      # This validates that the lock is available
      puts "\nTesting lock availability..."
      test_lock = connection.execute("SELECT pg_try_advisory_lock(#{lock_id})").first['pg_try_advisory_lock']
      
      if test_lock
        puts "✓ Successfully acquired test lock"
        # Immediately release it
        release_result = connection.execute("SELECT pg_advisory_unlock(#{lock_id})").first['pg_advisory_unlock']
        if release_result
          puts "✓ Successfully released test lock"
        else
          puts "⚠️  Warning: Failed to release test lock"
        end
      else
        puts "⚠️  ERROR: Lock is STILL held after terminating all connections!"
        puts "This suggests a zombie lock. Checking system catalog..."
        
        # Show what's holding it
        holder_query = <<-SQL
          SELECT 
            l.pid,
            l.locktype,
            l.objid,
            l.granted,
            a.state,
            a.query,
            a.application_name
          FROM pg_locks l
          LEFT JOIN pg_stat_activity a ON l.pid = a.pid
          WHERE l.locktype = 'advisory' 
            AND l.objid = #{lock_id};
        SQL
        
        holders = connection.execute(holder_query)
        if holders.any?
          puts "Lock is held by:"
          holders.each do |h|
            puts "  PID: #{h['pid']}, State: #{h['state']}, Query: #{h['query']}"
          end
        else
          puts "Lock not visible but still can't be acquired (race condition)"
        end
      end
      
      # Verify locks are cleared
      remaining_locks = connection.execute(all_locks_query)
      if remaining_locks.any?
        puts "\n⚠️  Warning: #{remaining_locks.count} advisory lock(s) still present"
        remaining_locks.each do |lock|
          marker = lock['objid'].to_i == lock_id ? " ← MIGRATION LOCK" : ""
          puts "  - PID: #{lock['pid']}, ObjID: #{lock['objid']}#{marker}"
        end
      else
        puts "\n✓ All advisory locks cleared"
      end
      
    else
      puts "Advisory lock clearing is only supported for PostgreSQL"
    end
  end
end
