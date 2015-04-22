class VisitCallbacks

  def self.after_save(visit)
    return if visit.no_schengen_callback
    visit.post_visits.each do |v|
      v.no_schengen_callback = true
      v.save
    end
  end

  def self.after_destroy(visit)
    visit.post_visits.each do |v|
      v.save
    end
  end

  def self.after_update(visit)
    visit.post_visits.each do |v|
      v.no_schengen_callback = true
      v.save
    end
  end
end



