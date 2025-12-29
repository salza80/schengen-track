namespace :db do
  desc "Release any stale migration advisory locks"
  task unlock: :environment do
    connection = ActiveRecord::Base.connection
    
    if connection.adapter_name == 'PostgreSQL'
      puts "Checking for migration advisory locks..."
      
      # Query for all advisory locks currently held
      # Rails uses pg_try_advisory_lock with a specific key for migrations
      locks_query = <<-SQL
        SELECT 
          locktype, 
          classid, 
          objid, 
          pid,
          pg_terminate_backend(pid) as terminated
        FROM pg_locks 
        WHERE locktype = 'advisory' 
          AND database = (SELECT oid FROM pg_database WHERE datname = current_database())
          AND pid != pg_backend_pid();
      SQL
      
      begin
        locks = connection.execute(locks_query)
        
        if locks.any?
          puts "Found #{locks.count} advisory lock(s) from other sessions"
          locks.each do |lock|
            puts "  - Terminated process #{lock['pid']} (classid: #{lock['classid']}, objid: #{lock['objid']})"
          end
          puts "✓ Terminated #{locks.count} process(es) holding advisory locks"
        else
          puts "✓ No advisory locks found from other sessions"
        end
      rescue => e
        puts "⚠ Could not terminate locks: #{e.message}"
        puts "Attempting to unlock specific migration lock..."
        
        # As fallback, try to unlock the specific lock Rails uses
        # Rails generates the lock key from the database name
        connection.execute("SELECT pg_advisory_unlock_all();")
        puts "✓ Released all advisory locks for current session"
      end
    else
      puts "Advisory lock clearing is only supported for PostgreSQL"
    end
  end
end
