namespace :db do
  desc "Check and fix migration status for people table"
  task fix_people_migration: :environment do
    connection = ActiveRecord::Base.connection
    
    puts "Ensuring people records exist for every user..."
    created_people = ensure_missing_primary_people
    puts "  Created #{created_people} missing primary people" if created_people.positive?

    puts "Normalizing primary person flags..."
    normalized_people = normalize_primary_people
    puts "  Updated #{normalized_people} people to enforce a single primary per user" if normalized_people.positive?

    puts "Attempting to backfill person_id columns before migration runs..."
    [:visits, :visas].each do |table|
      backfill_person_ids(connection, table)
    end

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

def ensure_missing_primary_people
  default_country_id = Country.find_by(country_code: 'US')&.id || Country.first&.id
  created = 0

  User.left_outer_joins(:people).where(people: { id: nil }).find_each(batch_size: 100) do |user|
    user.people.create!(
      first_name: user.first_name.presence || 'Traveler',
      last_name: user.last_name,
      nationality_id: user.nationality_id || default_country_id,
      is_primary: true
    )
    created += 1
  end

  created
end

def normalize_primary_people
  updates = 0

  User.includes(:people).find_each(batch_size: 100) do |user|
    people = user.people.to_a
    next if people.empty?

    primary_people = people.select(&:is_primary)

    if primary_people.empty?
      candidate = people.min_by(&:created_at)
      next unless candidate
      candidate.update_columns(is_primary: true)
      updates += 1
    elsif primary_people.size > 1
      keeper = primary_people.min_by(&:created_at)
      (primary_people - [keeper]).each do |person|
        person.update_columns(is_primary: false)
        updates += 1
      end
    end
  end

  updates
end

def backfill_person_ids(connection, table_name)
  unless connection.column_exists?(table_name, :person_id)
    puts "  Skipping #{table_name} (person_id column not present)"
    return
  end

  unless connection.column_exists?(table_name, :user_id)
    puts "  Skipping #{table_name} (user_id column already removed)"
    return
  end

  table = connection.quote_table_name(table_name)
  sql = <<~SQL.squish
    UPDATE #{table}
       SET person_id = primary_people.id
      FROM people AS primary_people
     WHERE primary_people.user_id = #{table}.user_id
       AND primary_people.is_primary = TRUE
       AND #{table}.person_id IS NULL;
  SQL

  updated = connection.update(sql)
  puts "  Backfilled #{updated} #{table_name} records" if updated.positive?

  remaining = connection.select_value("SELECT COUNT(*) FROM #{table} WHERE person_id IS NULL").to_i
  if remaining.zero?
    puts "  ✓ #{table_name} person_id values look good"
  else
    puts "  ⚠ #{remaining} #{table_name} rows still missing person_id values"
  end
rescue => e
  puts "  ⚠ Failed to backfill #{table_name}: #{e.message}"
end
