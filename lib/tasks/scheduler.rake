desc "Remove guest accounts more than a 6 hours old."
task :guest_cleanup => :environment do
  # delete all guest users over 2 days old
  todelete = User.where("updated_at <= :twodays AND guest=:istrue", { twodays: Time.now - 2.days, istrue: true })

  todelete.each do |u|
    u.people.each do |p|
      p.visits.each do |v|
        v.no_schengen_callback = true
        v.destroy
      end
    end
  end
  todelete.destroy_all

  # delete all guest users over 4 hours old with no visit data
  todelete = User.where("updated_at <= :fourhours AND guest=:istrue", { fourhours: Time.now - 4.hours, istrue: true })
  todelete.each do |u|
    del = false
    u.people.each do |p|
      del = true if p.visits.count > 0
    end
    u.destroy if del == true
  end
end
