namespace :db do
  desc "Check and fix migration status for people table"
  task fix_people_migration: :environment do
    connection = ActiveRecord::Base.connection
    
    puts "Checking migration status..."
    
    # Check if people table exists
    people_table_exists = connection.table_exists?(:people)
    puts "People table exists: #{people_table_exists}"
    
    # Check if migration is recorded as complete
    migration_version = '20251229034947'
    migration_exists = connection.select_value(
      "SELECT version FROM schema_migrations WHERE version = '#{migration_version}'"
    )
    puts "Migration #{migration_version} recorded: #{!migration_exists.nil?}"
    
    if people_table_exists && migration_exists.nil?
      puts "\n⚠ Table exists but migration not recorded!"
      puts "Marking migration as complete..."
      
      connection.execute(
        "INSERT INTO schema_migrations (version) VALUES ('#{migration_version}')"
      )
      
      puts "✓ Migration marked as complete"
    elsif people_table_exists && migration_exists
      puts "✓ Migration already complete"
    elsif !people_table_exists
      puts "⚠ Table doesn't exist yet - migration needs to run"
    end
    
    # Also check for the second migration
    migration_version_2 = '20251229035005'
    migration_exists_2 = connection.select_value(
      "SELECT version FROM schema_migrations WHERE version = '#{migration_version_2}'"
    )
    
    visits_person_column = connection.column_exists?(:visits, :person_id)
    visas_person_column = connection.column_exists?(:visas, :person_id)
    
    puts "\nVisits table has person_id: #{visits_person_column}"
    puts "Visas table has person_id: #{visas_person_column}"
    puts "Migration #{migration_version_2} recorded: #{!migration_exists_2.nil?}"
    
    if (visits_person_column || visas_person_column) && migration_exists_2.nil?
      puts "\n⚠ Schema changes exist but migration not recorded!"
      puts "Marking second migration as complete..."
      
      connection.execute(
        "INSERT INTO schema_migrations (version) VALUES ('#{migration_version_2}')"
      )
      
      puts "✓ Second migration marked as complete"
    end
  end
end
