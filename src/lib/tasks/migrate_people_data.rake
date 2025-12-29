namespace :db do
  desc "Migrate user data to people table in batches"
  task migrate_people_data: :environment do
    batch_size = ENV['BATCH_SIZE']&.to_i || 500
    
    puts "Starting people data migration..."
    puts "Batch size: #{batch_size}"
    
    # Count users without people
    total_users = User.count
    users_with_people = User.joins(:people).distinct.count
    users_without_people = total_users - users_with_people
    
    puts "Total users: #{total_users}"
    puts "Users with people: #{users_with_people}"
    puts "Users needing migration: #{users_without_people}"
    
    if users_without_people == 0
      puts "✓ All users already have people records. Nothing to migrate."
      next
    end
    
    # Process in batches
    total_migrated = 0
    batch_number = 0
    
    User.left_joins(:people)
        .where(people: { id: nil })
        .find_in_batches(batch_size: batch_size) do |user_batch|
      
      batch_number += 1
      puts "\nProcessing batch #{batch_number} (#{user_batch.size} users)..."
      
      # Build people data for this batch
      people_data = user_batch.map do |user|
        {
          user_id: user.id,
          first_name: user.first_name.presence || 'Guest',
          last_name: user.last_name,
          nationality_id: user.nationality_id,
          is_primary: true,
          created_at: user.created_at || Time.current,
          updated_at: user.updated_at || Time.current
        }
      end
      
      # Insert this batch
      Person.insert_all(people_data) if people_data.any?
      
      total_migrated += user_batch.size
      puts "✓ Batch #{batch_number} complete. Total migrated: #{total_migrated}/#{users_without_people}"
      
      # Small delay to avoid overwhelming the database
      sleep(0.1)
    end
    
    puts "\n✓ Migration complete! Created #{total_migrated} people records."
    
    # Save stats to temp file for API response
    stats = {
      total_users: total_users,
      migrated: total_migrated,
      batches: batch_number
    }
    File.write('/tmp/people_migration_stats.json', stats.to_json)
  end
end
