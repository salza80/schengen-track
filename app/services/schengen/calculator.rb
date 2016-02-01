require 'delegate'

module Schengen
  class Calculator

    attr_accessor :visits

    def initialize(person)
      @person = person
      @visits = @person.visits.to_a.collect {|v| v =  SchengenDecorator.new(v) }
    end

 

    def calculate
      return unless @person
      return if @visits.empty?
      if @person.nationality.visa_required == 'F'
        zero_schengen
      elsif @person.nationality.old_schengen_calc
        calculate_schengen_days_old
      else
        calculate_schengen_days_new
      end
    end

    def find_visit(id)
      @visits.each do |visit|
        return visit if visit.id == id
      end
      nil
    end

    private

    

    def zero_schengen
      @visits.each do |v| 
        v.schengen_days = 0
      end
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
        if prev_overstay_exit_date && (prev_overstay_exit_date + 180.days) >= v.entry_date
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
        if v.visit_check? == false && v.schengen?
          prev_overstay_exit_date = v.exit_date
          prev_overstay_schengen_days = v.schengen_days
        end
      end
    end


      def new_schengen_days_calc(visit)
        return visit.schengen_days = nil unless visit.exit_date
        # return visit.schengen_days = visit.no_days if visit.no_days > 180
        if visit.no_days > 180
          visit.schengen_days = visit.no_days if visit.schengen?
          return
        end
        previous_visits = visit.previous_180_days_visits.sort_by(&:entry_date)
        begin_date = visit.exit_date - 179.days
        schen_day_count = 0
        prev_exit_date = nil
        (previous_visits << visit).each do |v|
          next if v.exit_date<= begin_date
          if v.schengen? && v.exit_date <= visit.exit_date
            if v.entry_date < begin_date && v.exit_date >= begin_date
              schen_day_count += (v.exit_date - begin_date ).to_i + 1
            else
              schen_day_count += v.no_days
            end
            schen_day_count -= 1 if prev_exit_date == v.entry_date
          end
          prev_exit_date = v.exit_date
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

  class SchengenDecorator < SimpleDelegator

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

    #calculate how many days continuious in schengen zone
    def no_days_continuous_in_schengen
      return  0 unless exit_date
      return 0 unless schengen?
      visits = (previous_schengen_visits.sort_by(&:entry_date) << self).reverse!
      cont_days_cnt = 0
      prev_entry_date = nil
      visits.each do |v|
        if (v.exit_date - 1.day) == prev_entry_date || prev_entry_date.nil?
          cont_days_cnt += v.no_days
        elsif v.exit_date == prev_entry_date
          cont_days_cnt += v.no_days - 1
        else
          return cont_days_cnt
        end
        prev_entry_date = v.entry_date
      end
      cont_days_cnt
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
