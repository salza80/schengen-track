require 'delegate'

module Schengen
  # calculates schengen days and continious days in schengen area
  class Calculator

    attr_reader :visits
    def initialize(person)
      @person = person
      @visits = @person.visits.to_a.collect { |v| SchengenDecorator.new(v) }
      calculate
    end

    def calculate
      return unless @person
      return if @visits.empty?
      calc_no_days_continuous_in_schengen
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

    # schengen not applicable
    def zero_schengen
      @visits.each do |v|
        v.schengen_days = 0
      end
    end

    # Old schengen calculations for exception countrie
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
        if prev_overstay_exit_date &&
           (prev_overstay_exit_date + 180.days) >= v.entry_date
          if v.schengen?
            v.schengen_days = prev_overstay_schengen_days + v.no_days
            v.schengen_days -= 1 if v.entry_date == prev_overstay_exit_date
          else
            v.schengen_days = prev_overstay_schengen_days
          end
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
        next if v.exit_date <= begin_date
        if v.schengen? && v.exit_date <= visit.exit_date
          if v.entry_date < begin_date && v.exit_date >= begin_date
            schen_day_count += (v.exit_date - begin_date).to_i + 1
          else
            schen_day_count += v.no_days
          end
          schen_day_count -= 1 if prev_exit_date == v.entry_date
        end
        prev_exit_date = v.exit_date
      end
      visit.schengen_days = schen_day_count
    end

    # # calculate how many days continuious in schengen zone
    # def calc_no_days_continuous_in_schengen
    #   no_days_cnt = 0
    #   prev_exit_date = nil
    #   @visits.each do |v|
    #     if v.schengen? == false
    #       no_days_cnt = 0
    #     elsif  (v.entry_date - 1.day) == prev_exit_date || prev_exit_date.nil?
    #       no_days_cnt += v.no_days
    #     elsif  prev_exit_date == v.entry_date
    #       no_days_cnt += v.no_days - 1
    #     else
    #       no_days_cnt = v.no_days
    #     end
    #     v.no_days_continuous_in_schengen = no_days_cnt
    #     prev_exit_date = v.exit_date if v.schengen?
    #   end
    # end

     # calculate how many days continuious in schengen zone
    def calc_no_days_continuous_in_schengen
      prev_entry = nil
      prev_visit = nil
      @visits.each do |v|
        if v.schengen? == false
          v.no_days_continuous_in_schengen = 0
          prev_entry = nil
        elsif prev_entry.nil?
          v.no_days_continuous_in_schengen = v.no_days
          prev_entry = v
        elsif v.entry_date - prev_visit.exit_date >= 1
          v.no_days_continuous_in_schengen = v.no_days
          prev_entry = v
        else
          v.no_days_continuous_in_schengen = calc_num_days(prev_entry.entry_date, v.exit_date)
        end
        prev_visit = v if v.schengen?
      end
    end

    def calc_num_days(start_date, end_date)
      0 if start_date.nil? || end_date.nil?
      (end_date - start_date).to_i + 1
    end
  end
end
