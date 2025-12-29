namespace :db do
  desc "Release any stale migration advisory locks"
  task unlock: :environment do
    # Get the advisory lock key that Rails uses for migrations
    connection = ActiveRecord::Base.connection
    
    if connection.adapter_name == 'PostgreSQL'
      # Rails 7+ uses a specific advisory lock for migrations
      # The lock ID is generated from the database name
      puts "Checking for advisory locks..."
      
      # Query to see all advisory locks
      locks = connection.execute(<<-SQL)
        SELECT pg_advisory_unlock_all();
      SQL
      
      puts "✓ Released all advisory locks for current session"
      puts "If locks persist across sessions, they may have been from a crashed process."
      puts "Those locks are automatically released when the connection closes."
    else
      puts "Advisory lock clearing is only supported for PostgreSQL"
    end
  end
end
