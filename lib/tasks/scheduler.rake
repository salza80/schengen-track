namespace :db do
  desc 'Remove guest accounts.'
  task guest_cleanup: :environment do
    Rails.logger.info 'begin guest cleanup ' + Time.now.to_s
    Rails.logger.info 'Number of user accounts: ' + User.count.to_s
    Rails.logger.info 'Number of Visits: ' + Visit.count.to_s
    Rails.logger.info 'Number of Visas: ' + Visa.count.to_s

    puts 'begin guest cleanup ' + Time.now.to_s
    puts 'Number of user accounts: ' + User.count.to_s
    puts 'Number of Visits:' + Visit.count.to_s
    puts 'Number of Visas: ' + Visa.count.to_s


    ActiveRecord::Base.transaction do
      begin 
        # delete all guest users over 7 days old
        guestsDelete = User.where("updated_at <= :limit AND guest=:istrue", { limit: Time.now - 7.days, istrue: true }).select(:id).find_in_batches(batch_size: 100) do | ids |
          User.includes(:visits, :visas).where(id: ids).destroy_all
        end
        puts 'end guest cleanup'
        puts 'Number of user accounts: ' + User.count.to_s
        puts 'Number of Visits:' + Visit.count.to_s
        puts 'Number of Visas: ' + Visa.count.to_s
        puts 'Number of Users Deleted: ' + guestsDelete.count.to_s
      rescue => e
        Rails.logger.warn 'An error occured in guest cleanup ' + e.message
        puts 'an error occured!'
        puts e.message
      end
    end
  end
end
