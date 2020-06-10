namespace :db do
  desc 'Remove guest accounts.'
  task :guest_cleanup, [:limit_date] => :environment do | t, args |
    Rails.logger.info 'begin guest cleanup ' + Time.now.to_s
    Rails.logger.info 'Number of user accounts: ' + User.count.to_s
    Rails.logger.info 'Number of Visits: ' + Visit.count.to_s
    Rails.logger.info 'Number of Visas: ' + Visa.count.to_s

    puts 'begin guest cleanup ' + Time.now.to_s
    puts 'Number of user accounts: ' + User.count.to_s
    puts 'Number of Visits:' + Visit.count.to_s
    puts 'Number of Visas: ' + Visa.count.to_s

    args.with_defaults(:limit_date => Time.now - 7.days)

    ActiveRecord::Base.transaction do
      begin 
        # delete all guest users over 7 days old or up to the limit_date passed in.
        User.where("updated_at <= :limit AND guest=:istrue", { limit: args.limit_date, istrue: true }).select(:id).find_in_batches(batch_size: 100) do | ids |
          User.includes(:visits, :visas).where(id: ids).destroy_all
        end
        puts 'end guest cleanup'
        puts 'Number of user accounts: ' + User.count.to_s
        puts 'Number of Visits:' + Visit.count.to_s
        puts 'Number of Visas: ' + Visa.count.to_s
      rescue => e
        Rails.logger.warn 'An error occured in guest cleanup ' + e.message
        puts 'an error occured!'
        puts e.message
      end
    end
  end
end
