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
        if @user.old_schengen_calc
           "Old Calculation - 3 Month in and 6 Month Period"
        else
          "New Calculation - 90 days in last 180 days (rolling 180 days)"
        end
      end
      private
      def too_many_days?
        end_date - begin_date > 5000
      end

      def begin_date
        @visits.first.entry_date
      end

      def end_date
        @visits.last.exit_date + 360.days
      end

      def generate_days
        return unless @user
        @calculated_days = {}
        return if @visits.empty?
        return if too_many_days?
        count_180_day = 0
        schengen_days_in_last_180=0

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
          if @user.nationality.visa_required == 'F'
            puts "none"
          elsif @user.nationality.old_schengen_calc
            schengen_days_in_last_180, count_180_day = calc_schengen_day_old_count(sd,i,schengen_days_in_last_180, count_180_day)
          else
            sd.schengen_days_count=calc_schengen_day_new_count(sd,i)
          end
          i+=1
          break if visit.nil? && sd.schengen_days_count ==0
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
          if i >= 179
            count -= calculated_days[i-179].schengen_day_int
          end
        else
          if sd.schengen?
            sd.overstay_waiting = 0
          else
            sd.overstay_waiting = prev_sd.overstay_waiting + 1
          end

          if sd.overstay_waiting > 180
            count=0
            sd.overstay_waiting=0
          end
        end
        count
      end

      def calc_max_remaining_days
        return if @user.nationality.visa_required == 'F'
 
        if @user.nationality.old_schengen_calc
          calc_max_remaining_days_old
        else
          calc_max_remaining_days_new
        end
      end

      def calc_max_remaining_days_old
        #logic not right yet
        prev = nil
        @calculated_days.sort.reverse.each do |aday|
          day = aday[1]
          day.max_remaining_days =  90 - day.schengen_days_count
          unless prev
            prev = day
            next
          end
         
          if prev.max_remaining_days!= 0 && prev.max_remaining_days!= day.max_remaining_days
            @next_entry_days.unshift(prev)
          end

          if day.schengen?
            if prev.max_remaining_days!= 0 && prev.max_remaining_days== day.max_remaining_days
              @next_entry_days.unshift(prev)
            end
            return
          end
          prev = day
        end 
      end


      def calc_max_remaining_days_new
        prev = nil
        #track of last 180 days change
        aTracker = Array.new(90,0)
        @calculated_days.sort.reverse.each do |aday|
          day = aday[1]
          unless prev
            day.max_remaining_days =  90 - day.schengen_days_count
            prev = day
            next
          end

          if prev.schengen_days_count != day.schengen_days_count
            aTracker.unshift(1)
          else
            aTracker.unshift(0)
          end
          aTracker.pop()

         
          
          if day.schengen_days_count==90
            day.max_remaining_days=0
          else
            cnt = day.schengen_days_count
            a=0
            aTracker.each do |n|
              cnt = cnt + 1 
              cnt = cnt - n
              a = a+1
              break if cnt == 90
            end
            day.max_remaining_days =  a
          end

          if prev.max_remaining_days!= 0 && prev.max_remaining_days!= day.max_remaining_days
            @next_entry_days.unshift(prev)
          end

          if day.schengen?
            if prev.max_remaining_days!= 0 && prev.max_remaining_days== day.max_remaining_days
              @next_entry_days.unshift(prev)
            end
            return
          end
          prev = day

        end 

      end

      def calc_schengen_day_old_count(sd,i,schengen_days_in_last_180, count_180_day)
        if (count_180_day > 0 || sd.schengen?)
          count_180_day +=1
        end
        if count_180_day > 180
          if sd.schengen?
            schengen_days_in_last_180 += sd.schengen_day_int
          else
            count_180_day = 0
            schengen_days_in_last_180 = sd.schengen_day_int
          end
        else
          schengen_days_in_last_180 += sd.schengen_day_int
        end
        sd.schengen_days_count = schengen_days_in_last_180
        [schengen_days_in_last_180,count_180_day]
      end      
    end

    class SchengenDay
        attr_accessor :the_date, :entered_country, :stayed_country, :exited_country,  :schengen_days_count, :continuous_days_count, :overstay_waiting, :max_remaining_days, :notes

        def initialize(date)
          @the_date = date
          @overstay_waiting=0;

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
          return 0 if schengen_days_count <=90
          schengen_days_count - 90
        end

        def schengen?
          (entered_country && entered_country.schengen?(the_date)) || (stayed_country && stayed_country.schengen?(the_date)) || (exited_country && exited_country.schengen?(the_date))
        end

        def schengen_day_int 
          schengen? ? 1 : 0
        end

        def overstay?
          # return false unless schengen?
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
          name = ""
          if exited_country
            name += "Exited: " +  exited_country.name + " "
          end
          if entered_country
            name += "Entered: " + entered_country.name
          end
          name
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


   
