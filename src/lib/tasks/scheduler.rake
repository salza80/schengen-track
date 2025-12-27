namespace :db do
  desc 'Remove guest accounts.'
  task :guest_cleanup, [:limit_date, :max_batches] => :environment do | t, args |
    Rails.logger.info 'begin guest cleanup ' + Time.now.to_s
    Rails.logger.info 'Number of user accounts: ' + User.count.to_s
    Rails.logger.info 'Number of Visits: ' + Visit.count.to_s
    Rails.logger.info 'Number of Visas: ' + Visa.count.to_s

    puts 'begin guest cleanup ' + Time.now.to_s
    puts 'Number of user accounts: ' + User.count.to_s
    puts 'Number of Visits:' + Visit.count.to_s
    puts 'Number of Visas: ' + Visa.count.to_s

    args.with_defaults(:limit_date => Time.now - 7.days, :max_batches => nil)
    
    max_batches = args.max_batches ? args.max_batches.to_i : nil
    batches_processed = 0
    deleted_count = 0
    remaining_count = 0

    ActiveRecord::Base.transaction do
      begin 
        # delete all guest users over 7 days old or up to the limit_date passed in.
        User.where("updated_at <= :limit AND guest=:istrue", { limit: args.limit_date, istrue: true }).select(:id).find_in_batches(batch_size: 100) do | ids |
          User.includes(:visits, :visas).where(id: ids).destroy_all
          deleted_count += ids.size
          batches_processed += 1
          
          if max_batches && batches_processed >= max_batches
            remaining_count = User.where("updated_at <= :limit AND guest=:istrue", { limit: args.limit_date, istrue: true }).count
            puts "Reached max_batches limit (#{max_batches}). Deleted #{deleted_count} users. #{remaining_count} old guest users remaining."
            Rails.logger.info "Reached max_batches limit (#{max_batches}). Deleted #{deleted_count} users. #{remaining_count} old guest users remaining."
            break
          end
        end
        
        puts 'end guest cleanup'
        puts "Deleted #{deleted_count} guest users in #{batches_processed} batches"
        puts 'Number of user accounts: ' + User.count.to_s
        puts 'Number of Visits:' + Visit.count.to_s
        puts 'Number of Visas: ' + Visa.count.to_s
        
        # Store stats in temp file for controller to read
        stats = {
          deleted: deleted_count,
          batches: batches_processed,
          remaining: remaining_count
        }
        File.write('/tmp/guest_cleanup_stats.json', stats.to_json)
        
      rescue => e
        Rails.logger.warn 'An error occurred in guest cleanup ' + e.message
        puts 'an error occurred!'
        puts e.message
      end
    end
  end
end
