desc "Remove guest accounts more than a week old."
task :guest_cleanup => :environment do
  User.where("created_at <= :weekago AND guest = true",
  {weekago: Time.now - 1.week})
end
