require 'delegate'

module Schengen
  module Days
    # calculates schengen days and continious days in schengen area
    class Calculator
      def initialize(person)
        @person = person
        @visits = @person.visits.to_a
        @calculated_days={}
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
      else
        puts @calculated_days.inspect

      end
      end

      def total_schengen_days
        calculated_days.reduce(0){|sum,sd| sum += sd.schengen_day_int }
      end

      def calculated_days
        @calculated_days.values
      end

      def too_many_days?
        end_date - begin_date > 5000
      end

      private

      def begin_date
        @visits.first.entry_date
      end

      def end_date
        @visits.last.exit_date + 360.days
      end

      def generate_days
        return unless @person
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
            set_country(sd,visit)
            loop do
              break if visit.nil? || date < visit.exit_date
                v +=1
                visit = @visits[v]
               set_country(sd, visit)
            end
          end

          @calculated_days[sd.the_date]=sd
          sd.continuous_days_count = calc_continuous_days_count(sd, i)
          if @person.nationality.visa_required == 'F'
            puts "none"
          elsif @person.nationality.old_schengen_calc
            schengen_days_in_last_180, count_180_day = calc_schengen_day_old_count(sd,i,schengen_days_in_last_180, count_180_day)
          else
            sd.schengen_days_count=calc_schengen_day_new_count(sd,i)
          end
          i+=1
        end
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

      def set_country(schengen_day, visit)
        return if visit.nil?
        t = true
        if schengen_day.the_date == visit.entry_date
           schengen_day.entered_country = visit.country if schengen_day.entered_country.nil? || !schengen_day.entered_country.schengen?
           t=false
        end
        if schengen_day.the_date == visit.exit_date
           schengen_day.exited_country = visit.country if schengen_day.exited_country.nil? 
           t=false
        end
        if t && schengen_day.the_date.between?(visit.entry_date, visit.exit_date)
           schengen_day.stayed_country = visit.country
        end
      end
    end

    class SchengenDay
        attr_accessor :the_date, :entered_country, :stayed_country, :exited_country,  :schengen_days_count, :continuous_days_count, :overstay_waiting , :notes

        def initialize(date)
          @the_date = date
          @overstay_waiting=0;

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


   
