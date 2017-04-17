require 'delegate'

module Schengen
  # calculates schengen days and continious days in schengen area
  require 'csv'
  class Calculator

    attr_reader :visits
    def initialize(person)
      @person = person
      @visits = @person.visits.to_a.collect { |v| SchengenDecorator.new(v) }
      calculate_by_days
    end

    # def calculate
    #   return unless @person
    #   return if @visits.empty?
    #   calc_no_days_continuous_in_schengen
    #   if @person.nationality.visa_required == 'F'
    #     zero_schengen
    #   elsif @person.nationality.old_schengen_calc
    #     calculate_schengen_days_old
    #   else
    #     calculate_schengen_days_new
    #   end
    # end

    def to_csv
      CSV.generate(headers: :first_row) do |csv|

        header = []
        header << "Entry Date"
        header << "Exit Date"
        header << "Country"
        header << "In Shengen Area"
        header << "No Days"
        if @person.visa_required?
          header << "Visa Exists"
          header << "No. Entries"
          header << "Visa Overstay"
        end
        header << "Schengen Days Calculation"
        header << "Schengen Days Remaining"
        header << "Schengen Days Overstay"
        csv << header
        @visits.each do |visit|
          row = []
          row << visit.entry_date
          row << visit.exit_date
          row << visit.country.name
          row << visit.schengen? ? "Yes" : "No"
          row << visit.no_days
          if @person.visa_required?
            if visit.schengen? == false
              row << "NA"
            elsif visit.visa_exists?
              row << "Yes"
            else
             row << "No"
            end
            if visit.visa_exists?
               row << visit.visa_entry_count.to_s + " of " +  (visit.visa_entries_allowed == 0 ? "Multi" : visit.visa_entries_allowed.to_s)
            elsif visit.schengen? == false
               row << "N/A"
            else
              row << "Visa Required!"
            end
            row << visit.visa_overstay_days
          end
          row << visit.schengen_days.to_s + "  of 90 days"
          row << visit.schengen_days_remaining
          row << visit.schengen_overstay_days
          csv << row
        end
      end
    end



    def find_visit(id)
      @visits.each do |visit|
        return visit if visit.id == id
      end
      nil
    end

    private

    # schengen not applicable
    def zero_schengen
      @visits.each do |v|
        v.schengen_days = 0
      end
    end

    def calculate_by_days
      return unless @person
      return if @visits.empty?
       if @person.nationality.visa_required == 'F'
         zero_schengen
        else
          @day_calc = Schengen::Days::Calculator.new(@person)
          @visits.each do |v|
            last_day = @day_calc.find_by_date(v.exit_date)
            v.schengen_days = last_day.schengen_days_for_visit(v)
            v.no_days_continuous_in_schengen = last_day.continuous_days_for_visit(v)
          end
        end
    end

    # # Old schengen calculations for exception countrie
    # def calculate_schengen_days_old
    #   start_date = nil
    #   end_date = nil
    #   schengen_days_count = 0
    #   @visits.each do |v|
    #     if v.schengen?
    #       if start_date.nil? || (v.entry_date > end_date)
    #         start_date = v.entry_date
    #         end_date = start_date + 180.days
    #         schengen_days_count = v.no_days
    #       elsif v.entry_date <= end_date && v.exit_date > end_date
    #         schengen_days_count += (end_date - v.entry_date).to_i
    #         if schengen_days_count <= 90
    #           start_date = end_date + 1
    #           end_date = start_date + 180.days
    #           schengen_days_count = (v.exit_date - start_date).to_i
    #         end
    #         puts schengen_days_count
    #       else
    #         schengen_days_count += v.no_days
    #       end
    #     end
    #     v.schengen_days = schengen_days_count
    #   end
    # end

    # # New schengen calcuations for most countries
    # def calculate_schengen_days_new
    #   @visits.each do |v|
    #     new_schengen_days_calc(v)
    #   end
    #   prev_overstay_exit_date = nil
    #   prev_overstay_schengen_days = 0
      
    #   @visits.each do |v|
    #     if prev_overstay_exit_date &&
    #        (prev_overstay_exit_date + 180.days) >= v.entry_date
    #       if v.schengen?
    #         v.schengen_days = prev_overstay_schengen_days + v.no_days
    #         v.schengen_days -= 1 if v.entry_date == prev_overstay_exit_date
    #       else
    #         v.schengen_days = prev_overstay_schengen_days
    #       end
    #     else
    #       prev_overstay_exit_date = nil
    #       prev_overstay_schengen_days = 0
    #     end
    #     if v.visit_check? == false && v.schengen?
    #       prev_overstay_exit_date = v.exit_date
    #       prev_overstay_schengen_days = v.schengen_days
    #     end
    #   end
    # end

    # def new_schengen_days_calc(visit)
    #   return visit.schengen_days = nil unless visit.exit_date
    #   # return visit.schengen_days = visit.no_days if visit.no_days > 180
    #   if visit.no_days > 180
    #     visit.schengen_days = visit.no_days if visit.schengen?
    #     return
    #   end
    #   previous_visits = visit.previous_180_days_visits.sort_by(&:entry_date)
    #   begin_date = (visit.exit_date - 179.days)
    #   schen_day_count = 0
    #   prev_visit = nil
    #   (previous_visits << visit).each do |v|
    #     next if v.exit_date <= begin_date
    #     next if v.exit_date == v.entry_date && prev_visit && prev_visit.exit_date==v.entry_date && prev_visit.schengen?
    #     if v.schengen? && v.exit_date <= visit.exit_date
    #       if v.entry_date < begin_date && v.exit_date >= begin_date
    #         schen_day_count += (v.exit_date - begin_date).to_i + 1
    #       else
    #         schen_day_count += v.no_days
    #       end
    #       schen_day_count -= 1 if prev_visit && prev_visit.exit_date == v.entry_date
    #     end
    #     prev_visit = v
    #   end
    #   visit.schengen_days = schen_day_count
    # end

  

     # calculate how many days continuious in schengen zone
    # def calc_no_days_continuous_in_schengen
    #   prev_entry = nil
    #   prev_visit = nil
    #   @visits.each do |v| 
    #     if v.schengen? == false
    #       v.no_days_continuous_in_schengen = 0
    #       prev_entry = nil
    #     elsif prev_entry.nil?
    #       v.no_days_continuous_in_schengen = v.no_days
    #       prev_entry = v
    #     elsif v.entry_date - prev_visit.exit_date >= 1
    #       v.no_days_continuous_in_schengen = v.no_days
    #       prev_entry = v
    #     else
    #       v.no_days_continuous_in_schengen = calc_num_days(prev_entry.entry_date, v.exit_date)
    #     end
    #     prev_visit = v if v.schengen?
    #   end
    # end

    # def calc_num_days(start_date, end_date)
    #   0 if start_date.nil? || end_date.nil?
    #   (end_date - start_date).to_i + 1
    # end
  end
end
