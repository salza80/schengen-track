require 'delegate'

module Schengen
  # calculates schengen days and continious days in schengen area
  require 'csv'
  class Calculator

    attr_reader :visits
    def initialize(user)
      @user = user
      @visits = @user.visits.to_a.collect { |v| SchengenDecorator.new(v) }
      calculate_by_days
    end

    def to_csv
      CSV.generate(headers: :first_row) do |csv|

        header = []
        header << "Entry Date"
        header << "Exit Date"
        header << "Country"
        header << "In Shengen Area"
        header << "No Days"
        if @user.visa_required?
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
          if @user.visa_required?
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

     def next_entry_days
       return nil unless @day_calc
        @day_calc.next_entry_days
     end

    # Provide calendar data for sidebar/status blocks
    def calculated_days
      @day_calc&.calculated_days || []
    end

    def schengen_overstay?
      return false unless @day_calc
      @day_calc.schengen_overstay?
    end

    private

    # schengen not applicable
    def zero_schengen
      @visits.each do |v|
        v.schengen_days = 0
      end
    end

    def calculate_by_days
      return unless @user
      return if @visits.empty?
      if @user.nationality.visa_required == 'F'
        zero_schengen
      else
        @day_calc = Schengen::Days::Calculator.new(@user)
        @visits.each do |v|
          last_day = @day_calc.find_by_date(v.exit_date)
          v.schengen_days = last_day.schengen_days_for_visit(v)
          v.no_days_continuous_in_schengen = last_day.continuous_days_for_visit(v)
        end
      end
    end

  end
end
