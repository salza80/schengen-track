desc "Remove guest accounts more than a 6 hours old."
task :guest_cleanup => :environment do
   User.where("updated_at <= :sixhours AND guest=:istrue", {sixhours: Time.now - 6.hours, istrue: true}).delete_all
end
