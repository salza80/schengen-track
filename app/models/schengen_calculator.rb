class SchengenCalculator
  def initialize(person, visit = nil)
    @person = person
    if visit.nil?
      @visit = @person.visits.first
    else
      @visit = visit
    end
  end


  def calculate_schengen
    return unless @person
    return if @person.visits.empty?
    @visits = @person.visits
    if @person.nationality.visa_required == 'F'
      zero_schengen
    elsif @person.nationality.old_schengen_calc
      calculate_schengen_days_old
    else
      calculate_schengen_days_new
    end
    save_updates
    @visit.reload unless @visit.destroyed?
  end

private

def save_updates
  @visits.each do |v|
    v.no_schengen_callback = true
    v.save if v.changed?
  end
end

def zero_schengen 
  @visits.each do |v| 
    v.no_schengen_callback = true
    v.schengen_days = 0
  end
  @person.reload
end

# Old schengen calculations for exception countries

def calculate_schengen_days_old
  start_date = nil
  end_date = nil
  schengen_days_count = 0
  @visits.each do |v|
    if v.schengen?
      if start_date.nil? || (v.entry_date > end_date)
        start_date = v.entry_date
        end_date = start_date + 180.days
        schengen_days_count = v.no_days
      elsif v.entry_date <= end_date && v.exit_date > end_date
        schengen_days_count += end_date - v.entry_date
        if schengen_days_count <= 90
          start_date = end_date + 1
          end_date = start_date + 180.days
          schengen_days_count = v.exit_date - start_date
        end
      else
        schengen_days_count += v.no_days
      end
    end
    v.schengen_days = schengen_days_count
    v.no_schengen_callback = true
  end
end

# New schengen calcuations for most countries
def calculate_schengen_days_new
  @visits.each do |v|
    new_schengen_days_calc(v)
  end
  prev_overstay_exit_date = nil
  prev_overstay_schengen_days = 0
  
  @visits.each do |v|
    if prev_overstay_exit_date && (prev_overstay_exit_date + 91.days) >= v.entry_date
      if v.schengen?
        v.schengen_days = prev_overstay_schengen_days + v.no_days
        v.schengen_days -= 1 if v.entry_date == prev_overstay_exit_date
      else
        v.schengen_days = prev_overstay_schengen_days
      end
    # elsif v.exit_date.nil? == false
    #   if v.no_days > 180 && v.schengen?
    #     v.schengen_days = v.no_days - 90
    #   end
    else
      prev_overstay_exit_date = nil
      prev_overstay_schengen_days = 0
    end
    if v.visit_check? && v.schengen?
      prev_overstay_exit_date = v.exit_date
      prev_overstay_schengen_days = v.schengen_days
    end
  end
end


  def new_schengen_days_calc(visit)
    return visit.schengen_days = nil unless visit.exit_date
    # return visit.schengen_days = visit.no_days if visit.no_days > 180
    if visit.no_days > 180
      visit.schengen_days = visit.no_days
      return
    end
    previous_visits = visit.previous_180_days_visits.sort_by(&:entry_date)
    begin_date = visit.exit_date - 179.days
    schen_day_count = 0
    prev_exit_date = nil
    (previous_visits << visit).each do |v|
      if v.schengen? && v.exit_date <= visit.exit_date
        if v.entry_date < begin_date
          schen_day_count += (v.exit_date - begin_date).to_i + 1
        else
          schen_day_count += v.no_days
        end
        schen_day_count -= 1 if prev_exit_date == v.entry_date
        prev_exit_date = v.exit_date
      end
    end
    visit.schengen_days = schen_day_count
  end



  # def calculate_extra(visit)
  #   visa = Visa.find_schengen_visa(visit.entry_date, visa.exit_date)
  #   if visa
  #     new_schengen_calc(visit)
  #     return
  #   end
  #   visa = Visa.find_schengen_visa(visa.entry_date, nil)
  #   if visa.nil
  #     visit.schengen_days = (visit.no_days) * -1
  #     return
  #   end

  #   #Overstay


  # end

end
