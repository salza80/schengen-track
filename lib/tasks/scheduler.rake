namespace :db do
  desc 'Remove guest accounts more than a 2 days.'
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
        
        # delete all guest users over 1 month old
        todeletall = User.includes(:people).where("updated_at <= :onemonth AND guest=:istrue", { onemonth: Time.now - 1.day, istrue: true }).entries 

        # only delete if containts no visit
        todeletall.each do |u|
          Rails.logger.info 'deleting user ' + u.id.to_s + ' ' + u.people.first.first_name + ' ' + u.people.first.last_name
          puts 'deleting user ' + u.id.to_s + ' ' + u.people.first.first_name + ' ' + u.people.first.last_name 
          u.destroy!
        end


        # delete all guest users over 2 days old and without visits
        todeletesome = User.includes(:people => :visits ).where("updated_at <= :twodays AND guest=:istrue", { twodays: Time.now - 2.days, istrue: true })

        #only delete if containts no visits
        todeletesome.each do |u|
          del = true
          u.people.each do |p|
            if p.visits.count > 0
              del = false
              Rails.logger.info 'Do not delete user #{u.id} - #{u.people.first.first_name} #{u.people.first.last_name} with #{p.visits.count} visits recorded'
            end
          end
          if del
            Rails.logger.info 'deleting user ' + u.id.to_s + ' ' + u.people.first.first_name + ' ' + u.people.first.last_name
            puts 'deleting user ' + u.id.to_s + ' ' + u.people.first.first_name + ' ' + u.people.first.last_name
            u.destroy!
          end
        end
        raise ActiveRecord::Rollback
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
