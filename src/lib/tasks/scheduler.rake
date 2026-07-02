namespace :db do
  desc 'Remove guest accounts.'
  task :guest_cleanup, [:limit_date, :max_batches, :stats_file] => :environment do | t, args |
    args.with_defaults(:limit_date => Time.now - 30.days, :max_batches => nil, :stats_file => '/tmp/guest_cleanup_stats.json')

    limit_date = args.limit_date.presence || Time.now - 30.days
    max_batches = args.max_batches.present? ? args.max_batches.to_i : nil
    stats_file = args.stats_file.presence || '/tmp/guest_cleanup_stats.json'
    batches_processed = 0
    deleted_count = 0
    remaining_count = 0
    expired_rate_limits_deleted = 0
    lock_acquired = false
    connection = nil

    begin
      connection = ActiveRecord::Base.connection

      Rails.logger.info 'begin guest cleanup ' + Time.now.to_s
      Rails.logger.info 'Number of user accounts: ' + User.count.to_s
      Rails.logger.info 'Number of Visits: ' + Visit.count.to_s
      Rails.logger.info 'Number of Visas: ' + Visa.count.to_s

      puts 'begin guest cleanup ' + Time.now.to_s
      puts 'Number of user accounts: ' + User.count.to_s
      puts 'Number of Visits:' + Visit.count.to_s
      puts 'Number of Visas: ' + Visa.count.to_s

      if connection.adapter_name == 'PostgreSQL'
        lock_acquired = connection.select_value("SELECT pg_try_advisory_lock(hashtext('schengen_track_guest_cleanup'))")
        unless lock_acquired == true || lock_acquired.to_s == 't'
          raise 'Guest cleanup is already running'
        end

        puts 'Acquired guest cleanup advisory lock'
        Rails.logger.info 'Acquired guest cleanup advisory lock'
      end

      ActiveRecord::Base.transaction do
        # delete all guest users over 30 days old or up to the limit_date passed in.
        User.where("updated_at <= :limit AND guest=:istrue", { limit: limit_date, istrue: true }).select(:id).find_in_batches(batch_size: 100) do | ids |
          # For guest users, we bypass the prevent_last_person_deletion callback
          # by deleting people and their associations directly without callbacks
          user_ids = ids.map(&:id)

          # Delete visits and visas through people (using delete_all to skip callbacks)
          person_ids = Person.where(user_id: user_ids).pluck(:id)
          Visit.where(person_id: person_ids).delete_all
          Visa.where(person_id: person_ids).delete_all
          Person.where(id: person_ids).delete_all

          # Now delete the users
          User.where(id: user_ids).delete_all

          deleted_count += ids.size
          batches_processed += 1
          batch_message = "Deleted guest cleanup batch #{batches_processed}; #{deleted_count} users deleted so far"
          puts batch_message
          Rails.logger.info batch_message

          if max_batches && batches_processed >= max_batches
            remaining_count = User.where("updated_at <= :limit AND guest=:istrue", { limit: limit_date, istrue: true }).count
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
        expired_rate_limits_deleted = ApiRateLimit.table_exists? ? ApiRateLimit.delete_expired! : 0
        puts "Deleted #{expired_rate_limits_deleted} expired API rate limit rows"
        Rails.logger.info "Deleted #{expired_rate_limits_deleted} expired API rate limit rows"

        # Store stats in temp file for controller to read
        stats = {
          deleted: deleted_count,
          batches: batches_processed,
          remaining: remaining_count,
          expired_rate_limits_deleted: expired_rate_limits_deleted
        }
        File.write(stats_file, stats.to_json)
      end
    rescue => e
      message = "Guest cleanup failed: #{e.class}: #{e.message}"
      puts message
      Rails.logger.error message
      raise
    ensure
      if lock_acquired == true || lock_acquired.to_s == 't'
        begin
          connection.select_value("SELECT pg_advisory_unlock(hashtext('schengen_track_guest_cleanup'))")
          puts 'Released guest cleanup advisory lock'
          Rails.logger.info 'Released guest cleanup advisory lock'
        rescue => e
          message = "Failed to release guest cleanup advisory lock: #{e.class}: #{e.message}"
          puts message
          Rails.logger.warn message
        end
      end
    end
  end
end
