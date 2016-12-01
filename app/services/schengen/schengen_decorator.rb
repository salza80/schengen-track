module Schengen
  class SchengenDecorator < SimpleDelegator

    attr_accessor :schengen_days
    attr_accessor :no_days_continuous_in_schengen



    def visit_check?
      if visa_required?
        return visa_check?
      else
        return schengen_check?
      end
    end

    def schengen_days_remaining
      return nil unless schengen_days
      return 0 if visa_required? && visa_exists? == false
      return 90 - schengen_days if schengen_days <= 90
      0
    end

      # Checks schengen 90 days requirement (and continuious 90 day limit for old schengen calc)
    def schengen_check?
      schengen_overstay? == false && continuious_overstay? == false
    end

    # check if over 90 days
    def schengen_overstay?
      return schengen_days > 90 if schengen_days
      true
    end

    # number of days over the 90 day limit
    def schengen_overstay_days
      return nil unless schengen_days
      days = schengen_days
      days > 90 ? days - 90 : 0
    end

    # check if in zone for 90 days continuius
    def continuious_overstay?
      no_days_continuous_in_schengen > 90
    end

    # Number of days over continuious day stay limit
    def continuous_overstay_days
      days = continuous_overstay_days
      days > 90 ? days - 90 : 0
    end
    
     # check all requirements are satisfied when a visa is required
    def visa_check?
      schengen_overstay? == false && visa_overstay? == false
    end

    # check if visa has been overstayed by date
    def visa_date_overstay?
      return false unless visa_required?
      visa = schengen_visa
      return true unless visa
      exit_date >  visa.end_date
    end
    # check of the visa has been overstayed (either by date or number of entries)
    def visa_overstay?
      visa_date_overstay? || visa_entry_overstay?
    end

    # number of days overstay if has been overstayed by da
    def visa_overstay_days
      if visa_entry_overstay?
        return no_days
      elsif visa_date_overstay?
        return visa_date_overstay_days
      else
        0
      end
    end

    # number of days overstay if visa dates have been overstayed
    def visa_date_overstay_days
      return nil unless exit_date
      return 0 unless visa_date_overstay?
      visa = schengen_visa
      return no_days unless visa
      exit_date <= visa.end_date ? 0 : exit_date - visa.end_date
    end
    # check if visa has been overstayed by number of entry limit
    def visa_entry_overstay?
      return false unless person.visa_required? && schengen?
      return true unless visa_exists?
      visa = schengen_visa
      visa.no_entries != 0 && visa_entry_count > visa.no_entries
    end

    # number of visits on current visa
    def visa_entry_count
      p = previous_visits_on_current_visa << self
      return nil unless p
      cnt = 0
      prev_visit = nil
      p.each do |v|
        if v.schengen?
          if prev_visit.nil? == false && prev_visit.schengen?
            cnt += 1 if v.entry_date - prev_visit.exit_date > 1
          else
            cnt += 1
          end
        end
        prev_visit = v
      end
      cnt
    end
  end
end
