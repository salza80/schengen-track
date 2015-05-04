class SchengenCalculator
  def initialize(visit)
    @visit = visit
    @person = visit.person
  end


  def calculate_schengen
    if @visit.person.nationality.visa_required == 'F'
        zero_schengen
        return
      end
      if @visit.person.nationality.old_schengen_calc
        calculate_schengen_days_old
      else
        calculate_schengen_days_new
      end
  end


private

def zero_schengen 
  @person.visits.all.each do |v| 
    v.no_schengen_callback = true
    v.schengen_days = 0 
    v.save
  end
  @person.reload
  @visit.reload
end

#Old schengen calculations for exception countries

def calculate_schengen_days_old
  return unless @person
  return if @person.visits.all.count == 0
  start_date = nil
  end_date = nil
  schengen_days_count = 0
  @person.visits.all.each do |v|
    if v.country.schengen?
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
  @visit.reload
end



#New schengen calcuations for most countries
  def calculate_schengen_days_new
    return false unless @visit
    @visit.schengen_days = new_schengen_calc(@visit)
    @visit.no_schengen_callback = true
    @visit.save
    calculate_post_visits_new
  end

  def calculate_post_visits_new
    return false unless @visit
    @visit.post_visits.each do |v|
      v.no_schengen_callback = true
      v.schengen_days = new_schengen_calc(v)
      v.save
    end
  end

  def new_schengen_calc(visit)
    return nil unless visit.exit_date
    previous_visits = visit.previous_180_days_visits.sort_by(&:entry_date)
    return 0 unless previous_visits
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
    schen_day_count
  end
end
