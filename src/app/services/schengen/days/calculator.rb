require 'delegate'

module Schengen
  module Days
    # calculates schengen days and continious days in schengen area
   
    class Calculator
      # Maximum calculation span: ±20 years (20 past + 20 future = 40 years total)
      MAX_CALCULATION_DAYS = 40.years.to_i
      
      attr_reader :next_entry_days
      def initialize(person)
        @person = person
        @visits = @person.visits.to_a
        @calculated_days={}
        @next_entry_days=[]
        @person_requires_visa = @person.visa_required?
        @person_visas = @person_requires_visa ? @person.visas.schengen.to_a : []
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
        # With ±20 year cleanup (20 years past + 20 years future), max span is 40 years
        end_date - begin_date > MAX_CALCULATION_DAYS
      end

      def begin_date
        @visits.first.entry_date
      end

      def end_date
        # Always calculate through today or 190 days after last visit, whichever is later
        # This ensures status summary always has today's data
        [Time.zone.today, @visits.last.exit_date + 190.days].max
      end

      def generate_days
        return unless @person
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
          
          # Track visa information if person requires visa
          if @person_requires_visa
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
          
          if @person.nationality.visa_required == 'F'
            # Freedom of movement: users who do not require a visa are not subject to Schengen day counting.
          else
            # Visa required: perform Schengen day counting for this day.
            sd.schengen_days_count=calc_schengen_day_new_count(sd,i)
          end
          i+=1
          # Break early only if we've passed today AND no more visits with 0 Schengen days
          break if visit.nil? && sd.schengen_days_count == 0 && date > Time.zone.today
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
        if i == 0
          return sd.schengen_day_int
        end
        prev_sd = calculated_days[i-1]
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
        return if @person.nationality.visa_required == 'F'
        calc_max_remaining_days_new
      end

      # Calculates the maximum remaining days allowed in the Schengen area for each day in the tracking period.
      #
      # This method works backwards through the calculated days (from most recent to oldest) and determines
      # how many more days can be spent in the Schengen area before hitting the 90/180 day limit.
      #
      # The calculation uses a rolling window tracker (array of 90 elements) to monitor changes in Schengen
      # day counts over the last 180 days. For each day, it simulates forward to find when the 90-day limit
      # would be reached.
      #
      # Side effects:
      # - Sets the `max_remaining_days` attribute on each day object
      # - Populates the `@next_entry_days` array with significant dates where entry conditions change:
      #   * Days when overstay waiting period ends (transitions from waiting to allowed)
      #   * Days when max_remaining_days changes (except when already at limit)
      #   * The last day when entering the Schengen area while at the same max_remaining_days
      #     (this marks the optimal entry point and breaks out of the entire loop)
      #
      # @return [void]
      # @note The `break` statement exits the entire loop, not just the current iteration
      def calc_max_remaining_days_new
        last_entry_found = false
        prev = nil
        #track of last 180 days change of schengen days
        rolling_window_tracker = Array.new(90,0)
        @calculated_days.sort.reverse.each do |aday|
          day = aday[1]
          unless prev
            day.max_remaining_days =  90 - day.schengen_days_count
            prev = day
            next
          end
          if prev.schengen_days_count != day.schengen_days_count
            rolling_window_tracker.unshift(1)
          else
            rolling_window_tracker.unshift(0)
          end
          rolling_window_tracker.pop()

          if prev.overstay_waiting === 0 && day.overstay_waiting > 0
            @next_entry_days.unshift(prev)
          end

 
          if day.schengen_days_count == 90 || day.overstay? || day.overstay_waiting > 0
            day.max_remaining_days=0
          else
            cnt = day.schengen_days_count
            days_until_limit = 0
            rolling_window_tracker.each do |n|
              cnt = cnt + 1 
              cnt = cnt - n
              days_until_limit = days_until_limit + 1
              break if cnt == 90
            end
            day.max_remaining_days = days_until_limit
          end
          if prev.max_remaining_days!= 0 && prev.max_remaining_days!= day.max_remaining_days
            @next_entry_days.unshift(prev) if !last_entry_found
          end
            if day.overstay_waiting && !prev.overstay_waiting    
              @next_entry_days.unshift(prev) if !last_entry_found
            end

            if day.schengen? 
              if prev.max_remaining_days!= 0 && prev.max_remaining_days== day.max_remaining_days
                @next_entry_days.unshift(prev) if !last_entry_found                
              end
              last_entry_found = true
          end
          prev = day

        end 

      end

      def find_visa_for_date(date)
        return nil unless @person_requires_visa
        @person_visas.find { |v| date.between?(v.start_date, v.end_date) }
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
          @overstay_waiting = 0
          @user_requires_visa = false
          @schengen_days_count = 0
          @continuous_days_count = 0
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


   
