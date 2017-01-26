namespace :db do
  desc 'Remove guest accounts.'
  task guest_cleanup: :environment do
    Rails.logger.info 'begin guest cleanup ' + Time.now.to_s
    Rails.logger.info 'Number of user accounts: ' + User.count.to_s
    Rails.logger.info 'Number of People: ' + Person.count.to_s
    Rails.logger.info 'Number of Visits: ' + Visit.count.to_s
    Rails.logger.info 'Number of Visas: ' + Visa.count.to_s

    puts 'begin guest cleanup ' + Time.now.to_s
    puts 'Number of user accounts: ' + User.count.to_s
    puts 'Number of People: ' + Person.count.to_s
    puts 'Number of Visits:' + Visit.count.to_s
    puts 'Number of Visas: ' + Visa.count.to_s

    ActiveRecord::Base.transaction do
      begin 
        # delete all guest users over 10 days old
        todeletall = User.includes(:people).where("updated_at <= :limit AND guest=:istrue", { limit: Time.now - 10.days, istrue: true }).entries 

        todeletall.each do |u|
          Rails.logger.info 'deleting user ' + u.id.to_s
          puts 'deleting user ' + u.id.to_s
          u.destroy!
        end

        # delete all guest users over 1 day old and without visits
        todeletesome = User.includes(:people => :visits ).where("updated_at <= :limit AND guest=:istrue", { limit: Time.now - 1.days, istrue: true })

        #only delete if containts no visits
        todeletesome.each do |u|
          del = true
          u.people.each do |p|
            if p.visits.count > 0
              del = false
            end
          end
          if del
            Rails.logger.info 'deleting user ' + u.id.to_s
            puts 'deleting user ' + u.id.to_s
            u.destroy!
          end
        end
      rescue => e
        Rails.logger.warn 'An error occured in guest cleanup ' + e.message
        puts 'an error occured!'
        puts e.message
      end
    end
    
    
    puts 'end guest cleanup'
    puts 'Number of user accounts: ' + User.count.to_s
    puts 'Number of People: ' + Person.count.to_s
    puts 'Number of Visits:' + Visit.count.to_s
    puts 'Number of Visas: ' + Visa.count.to_s
  end
end
