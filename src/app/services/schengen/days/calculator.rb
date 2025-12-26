require 'delegate'

module Schengen
  module Days
    # calculates schengen days and continious days in schengen area
   
    class Calculator
      attr_reader :next_entry_days
      def initialize(user)
        @user = user
        @visits = @user.visits.to_a
        @calculated_days={}
        @next_entry_days=[]
        @user_requires_visa = @user.visa_required?
        @user_visas = @user_requires_visa ? @user.visas.schengen.to_a : []
        generate_days
      end

      def find_visit(id)
        @visits.each do |visit|
          return visit if visit.id == id
        end
        nil
      end

      def find_by_date(date)
         a = @calculated_days[date]
        if a
          return a
        end
      end

      def schengen_overstay?
        @calculated_days.each_value do |day|
          return true if day.overstay?
        end
        false
      end

      def total_schengen_days
        calculated_days.reduce(0){|sum,sd| sum += sd.schengen_day_int }
      end

      def calculated_days
        @calculated_days.values
      end  

      def calc_type_desc
        "90 days in last 180 days (rolling 180 days)"
      end
      private
      def too_many_days?
        # 40 years = ~14,600 days
        # With ±20 year cleanup, max realistic span is ~20 years
        end_date - begin_date > 14600
      end

      def begin_date
        @visits.first.entry_date
      end

      def end_date
        # Always calculate through today or 190 days after last visit, whichever is later
        # This ensures status summary always has today's data
        [Date.today, @visits.last.exit_date + 190.days].max
      end

      def generate_days
        return unless @user
        @calculated_days = {}
        return if @visits.empty?
        return if too_many_days?

        v = 0    
        i = 0
        begin_date.upto(end_date) do | date |
          visit =  @visits[v]
          sd = SchengenDay.new(date)

          #set the country/s
          unless visit.nil?
            sd.set_country(visit)
            loop do
              break if visit.nil? || date < visit.exit_date
                v +=1
                visit = @visits[v]
                sd.set_country(visit)
            end
          end

          @calculated_days[sd.the_date]=sd
          sd.continuous_days_count = calc_continuous_days_count(sd, i)
          
          # Track visa information if user requires visa
          if @user_requires_visa
            sd.user_requires_visa = true
            if sd.schengen?
              # Find visa for this date
              sd.visa = find_visa_for_date(sd.the_date)
              if sd.visa
                sd.visa_entries_allowed = sd.visa.no_entries
                sd.visa_entry_count = calc_visa_entry_count(sd.the_date, sd.visa)
              end
            end
          end
          
          if @user.nationality.visa_required == 'F'
            # Freedom of movement: users who do not require a visa are not subject to Schengen day counting.
          else
            # Visa required: perform Schengen day counting for this day.
            sd.schengen_days_count=calc_schengen_day_new_count(sd,i)
          end
          i+=1
          # Break early only if we've passed today AND no more visits with 0 Schengen days
          break if visit.nil? && sd.schengen_days_count == 0 && date > Date.today
        end
       calc_max_remaining_days
      end

      def calc_continuous_days_count(sd, i)
        return 0 unless sd.schengen?
        return sd.schengen_day_int if i==0
        calculated_days[i-1].continuous_days_count + 1
      end

      def calc_schengen_day_new_count(sd,i)
        # byebug
        return sd.schengen_day_int if i == 0
        prev_sd =  calculated_days[i-1]
        count = prev_sd.schengen_days_count + sd.schengen_day_int
        if !prev_sd.overstay?
          if i >= 180
            count -= calculated_days[i-180].schengen_day_int
          end
        else
          if sd.schengen?
            sd.overstay_waiting = 0
          else
            sd.overstay_waiting = prev_sd.overstay_waiting + 1
          end

          if sd.overstay_waiting >= 180
            count=0
            sd.overstay_waiting=0
          end
        end
        count
      end

      def calc_max_remaining_days
        return if @user.nationality.visa_required == 'F'
        calc_max_remaining_days_new
      end

      def calc_max_remaining_days_new
        # Sort days chronologically (forward in time)
        sorted_days = @calculated_days.sort_by { |date, day| date }
        
        # Calculate max_remaining_days for each day
        sorted_days.each do |(date, day)|
          # Skip if already at or over 90 days
          if day.schengen_days_count >= 90
            day.max_remaining_days = 0
            next
          end
          
          # Simulate staying consecutive days starting from this date
          current_count = day.schengen_days_count
          max_days = 0
          
          # Try staying for up to 90 days (or until we hit the limit)
          0.upto(89) do |k|
            simulated_date = date + k.days
            
            # Add 1 for staying this day
            current_count += 1
            
            # Subtract the day that falls off the 180-day rolling window
            day_falling_off_date = simulated_date - 180.days
            falling_off_day = @calculated_days[day_falling_off_date]
            if falling_off_day
              current_count -= falling_off_day.schengen_day_int
            end
            
            # If we've exceeded 90 days, we can't stay this day (but could stay previous days)
            if current_count > 90
              max_days = k
              break
            end
            
            # Otherwise we can stay at least this many days (including day k, so k+1 total)
            max_days = k + 1
          end
          
          day.max_remaining_days = max_days
        end
        
        # Build next_entry_days list - days when you should consider entering
        prev_day = nil
        sorted_days.each do |(date, day)|
          # Skip if in Schengen, in warning period, or no days available
          next if day.schengen? || day.warning? || day.max_remaining_days == 0
          
          # Only include future dates (today or later)
          next if date < Date.today
          
          # Add to next_entry_days if this is a good entry point:
          # - First day outside Schengen with available days, or
          # - Previous day was in Schengen, or
          # - max_remaining_days changed from previous day
          if prev_day.nil? || prev_day.schengen? || prev_day.max_remaining_days != day.max_remaining_days
            @next_entry_days << day
          end
          
          prev_day = day
        end
      end

      def find_visa_for_date(date)
        return nil unless @user_requires_visa
        @user_visas.find { |v| date.between?(v.start_date, v.end_date) }
      end

      def calc_visa_entry_count(current_date, visa)
        return nil unless visa
        
        # Get all visits on this visa up to current date
        visits_on_visa = []
        @visits.each do |visit|
          next unless visit.schengen?
          next unless visit.entry_date <= current_date
          
          # Check if visit's entry date falls within visa period
          visit_visa = find_visa_for_date(visit.entry_date)
          visits_on_visa << visit if visit_visa == visa
        end
        
        # Count distinct entries (consecutive visits = one entry)
        count = 0
        prev_visit = nil
        visits_on_visa.sort_by(&:entry_date).each do |v|
          # New entry if: first visit OR gap > 1 day after previous exit
          if prev_visit.nil? || v.entry_date - prev_visit.exit_date > 1
            count += 1
          end
          prev_visit = v
        end
        count
      end

    end

    class SchengenDay
        attr_accessor :the_date, :entered_country, :stayed_country, :exited_country,  :schengen_days_count, :continuous_days_count, :overstay_waiting, :max_remaining_days, :notes, :visa, :visa_entry_count, :visa_entries_allowed, :user_requires_visa

        def initialize(date)
          @the_date = date
          @overstay_waiting=0;
          @user_requires_visa = false
        end

        def set_country(visit)
          return if visit.nil?
          t = true
          if @the_date == visit.entry_date
             @entered_country = visit.country if entered_country.nil? || !entered_country.schengen?
             t=false
          end
          if @the_date == visit.exit_date
             @exited_country = visit.country if exited_country.nil? 
             t=false
          end
          if t && @the_date.between?(visit.entry_date, visit.exit_date)
             @stayed_country = visit.country
          end
        end
        def hasCountry?
          @entered_country || @exited_country || @stayed_country
        end

        def remaining_wait
          return nil if overstay_waiting == 0
          179 - overstay_waiting
        end

        def country_desc
          stayed_country.name if stayed_country
        end

        def overstay?
          overstay_days > 90
        end

        def overstay_days
          return 0 if schengen_days_count.nil? || schengen_days_count <= 90
          schengen_days_count - 90
        end

        def schengen?
          (entered_country && entered_country.schengen?(the_date)) || (stayed_country && stayed_country.schengen?(the_date)) || (exited_country && exited_country.schengen?(the_date))
        end

        def schengen_day_int 
          schengen? ? 1 : 0
        end

        def overstay?
          return false if schengen_days_count.nil?
          schengen_days_count > 90
        end

        def warning?
          !remaining_wait.nil?
        end

        def danger?
          (overstay? && schengen?)
        end

        def country_name
          return stayed_country.name if stayed_country
          if exited_country && entered_country
            if exited_country === entered_country
              return "Entered and Exited: " + exited_country.name
            end
            return "Entered: " + entered_country.name + " Exited: " +  exited_country.name
          end
          return exited_country.name if exited_country
          return entered_country.name if entered_country
          return "Outside Schengen"
        end

        def schengen_days_for_visit(v)
          return schengen_days_count  if v.entry_date == v.exit_date
          return schengen_days_count if !from_non_to_schengen?
          return schengen_days_count - 1
        end

        def continuous_days_for_visit(v)
          return continuous_days_count  if v.entry_date == v.exit_date
          return continuous_days_count if !from_non_to_schengen?
          0
        end

        def entered_schengen?
          return false unless entered_country
          return false unless entered_country.schengen?(the_date)
          return false if exited_country == entered_country
          return true unless exited_country
          return !exited_country.schengen?
        end

        def exited_schengen?
          return false unless exited_country
          return false unless exited_country.schengen?(the_date)
          return false if exited_country == entered_country
          return true unless entered_country
          return !entered_country.schengen?(the_date)
        end

        def user_requires_visa?
          @user_requires_visa == true
        end

        def visa_valid?
          return true unless user_requires_visa?
          return false if schengen? && visa.nil?
          return true unless visa
          the_date.between?(visa.start_date, visa.end_date)
        end

        def visa_entry_valid?
          return true unless visa_entries_allowed
          return true if visa_entries_allowed == 0  # Unlimited
          visa_entry_count <= visa_entries_allowed
        end

        def visa_warning?
          return false unless user_requires_visa?
          !visa_valid? || !visa_entry_valid?
        end

        def has_limited_entries?
          visa_entries_allowed && visa_entries_allowed > 0
        end

        private
        def from_non_to_schengen?
          return false if stayed_country
          return false unless entered_country && exited_country
          return false if exited_country.schengen?(the_date)
          !exited_country.schengen?(the_date) && entered_country.schengen?(the_date)
        end
    end
  end
end


   
