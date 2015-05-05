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
    if @person.nationality.visa_required == 'F'
      zero_schengen
      return
    end
    if @person.nationality.old_schengen_calc
      calculate_schengen_days_old
    else
      calculate_schengen_days_new
    end
    @visit.reload unless @visit.destroyed?
  end


private

def zero_schengen 
  @person.visits.all.each do |v| 
    v.no_schengen_callback = true
    v.schengen_days = 0
    v.over_stay_days = 0
    v.visa_entry_count = 0
    v.must_exit_date = nil
    v.next_possible_entry_date = nil
    v.save
  end
  @person.reload
  @visit.reload unless @visit.destroyed?
end

#Old schengen calculations for exception countries

def calculate_schengen_days_old
  return unless @person
  return if @person.visits.all.count == 0
  start_date = nil
  end_date = nil
  schengen_days_count = 0
  @person.visits.all.each do |v|
    if v.country.schengen?(v.entry_date)
      if start_date.nil? || (v.entry_date > end_date)
        start_date = v.entry_date
        end_date = start_date + 180.days
        schengen_days_count = v.no_days
      elsif v.entry_date <= end_date && v.exit_date > end_date
        schengen_days_count += end_date - v.entry_date
        if schengen_days_count <= 90
          start_date = end_date + 1
          end_date = start_date = 180.days
          schengen_days_count = v.exit_date - start_date
        end
      else
        schengen_days_count += v.no_days
      end
    end
    v.schengen_days = schengen_days_count
    v.no_schengen_callback = true
    v.save
  end
  @visit.reload unless @visit.destroyed?
end



#New schengen calcuations for most countries
  def calculate_schengen_days_new
    return false unless @visit
    @person.visits.all.each do |v|
      v.no_schengen_callback = true
      new_schengen_days_calc(v)
      v.save
    end
  end


  def new_schengen_days_calc(visit)
    return visit.schengen_days = nil unless visit.exit_date
    previous_visits = visit.previous_180_days_visits.sort_by(&:entry_date)
    begin_date = visit.exit_date - 180.days
    schen_day_count = 0
    prev_exit_date = nil
    (previous_visits << visit).each do |v|
      if v.country.schengen?(v.entry_date) && v.exit_date <= visit.exit_date
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
