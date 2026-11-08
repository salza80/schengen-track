require 'delegate'

module Schengen
  module Days
    # calculates schengen days and continious days in schengen area
   
    class Calculator
      class SpanTooLarge < ArgumentError; end
      # Date subtraction returns days: allow the ±20-year window plus forecast.
      MAX_CALCULATION_DAYS = 40 * 366 + 190
      
      attr_reader :next_entry_days
      def initialize(person, visits: nil, visa_history: nil)
        @person = person
        source = visits || @person.visits
        source = source.includes(:country) if source.is_a?(ActiveRecord::Relation)
        @visits = source.to_a
        @calculated_days={}
        @schengen_day_flags = []
        @next_entry_days=[]
        @freedom_of_movement = @person.nationality.visa_required == 'F'
        @person_requires_visa = @person.visa_required?
        @visa_history = visa_history || VisaHistory.new(@person) if @person_requires_visa
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

      # Length of a hypothetical stay starting on date, including arrival.
      # Only recorded days before arrival can consume or release its allowance.
      def maximum_stay_from(date)
        return nil if @freedom_of_movement
        day = find_by_date(date)
        return 90 unless day
        return 0 if day.overstay? || day.overstay_waiting.positive?

        used = day.schengen_days_count - day.schengen_day_int
        historical_index = (date - begin_date).to_i - 180
        90.times do |offset|
          expiring_index = historical_index + offset
          used -= @schengen_day_flags[expiring_index] if offset.positive? && expiring_index >= 0
          used += 1
          return offset if used > 90
        end
        90
      end
      private
      def too_many_days?
        # The web calculator supplies its supported date window without purging history.
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
        raise SpanTooLarge, 'Calculation span exceeds the supported day limit' if too_many_days?

        v = 0    
        i = 0
        begin_date.upto(end_date) do | date |
          visit =  @visits[v]
          sd = SchengenDay.new(date, freedom_of_movement: @freedom_of_movement)

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
          @schengen_day_flags << sd.schengen_day_int
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
          
          unless @freedom_of_movement
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
        @calculated_days[sd.the_date - 1].continuous_days_count + 1
      end

      def calc_schengen_day_new_count(sd,i)
        # byebug
        if i == 0
          return sd.schengen_day_int
        end
        prev_sd = @calculated_days[sd.the_date - 1]
        count = prev_sd.schengen_days_count + sd.schengen_day_int
        if !prev_sd.overstay?
          if i >= 180
            count -= @calculated_days[sd.the_date - 180].schengen_day_int
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
        return if @freedom_of_movement

        last_entry_found = false
        following = nil
        @calculated_days.values.reverse_each do |day|
          # An occupied day is already counted; its remaining days start tomorrow.
          arrival = day.schengen? ? day.the_date + 1 : day.the_date
          day.max_remaining_days = maximum_stay_from(arrival)
          if following
            waiting_ended = following.overstay_waiting.zero? && day.overstay_waiting.positive?
            changed = following.max_remaining_days != day.max_remaining_days
            entry_option = !last_entry_found && following.max_remaining_days.positive? && (changed || day.schengen?)
            if waiting_ended || entry_option
              @next_entry_days.unshift(following)
            end
          end
          last_entry_found = true if day.schengen?
          following = day
        end
      end

      def find_visa_for_date(date)
        return nil unless @person_requires_visa
        @visa_history.visa_for_date(date)
      end

      def calc_visa_entry_count(current_date, visa)
        return nil unless visa
        @visa_history.entry_count_on(current_date, visa)
      end

    end

    class SchengenDay
        attr_accessor :the_date, :entered_country, :stayed_country, :exited_country,  :schengen_days_count, :continuous_days_count, :overstay_waiting, :max_remaining_days, :notes, :visa, :visa_entry_count, :visa_entries_allowed, :user_requires_visa

        def initialize(date, freedom_of_movement: false)
          @the_date = date
          @freedom_of_movement = freedom_of_movement
          @overstay_waiting = 0
          @user_requires_visa = false
          @schengen_days_count = 0
          @continuous_days_count = 0
        end

        def freedom_of_movement?
          @freedom_of_movement
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


   
