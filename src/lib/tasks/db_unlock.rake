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
      
      # Strategy: Terminate ALL other connections to force release of locks
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
      sleep 0.5
      
      # Verify locks are cleared
      remaining_locks = connection.execute(all_locks_query)
      if remaining_locks.any?
        puts "\n⚠️  Warning: #{remaining_locks.count} advisory lock(s) still present after termination"
        remaining_locks.each do |lock|
          puts "  - PID: #{lock['pid']}, ObjID: #{lock['objid']}"
        end
      else
        puts "\n✓ All advisory locks cleared"
      end
      
    else
      puts "Advisory lock clearing is only supported for PostgreSQL"
    end
  end
end
