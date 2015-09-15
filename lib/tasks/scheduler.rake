desc "Remove guest accounts more than a 6 hours old."
task :guest_cleanup => :environment do
  todelete = User.where("updated_at <= :sixhours AND guest=:istrue", { sixhours: Time.now - 6.hours, istrue: true })

  todelete.each do |u|
    u.people.each do |p|
      p.visits.each do |v|
        v.no_schengen_callback = true
        v.destroy
      end
    end
  end
  todelete.destroy_all
end
