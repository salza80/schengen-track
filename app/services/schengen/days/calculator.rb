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
        # calc_schengen_days
      end

      def find_visit(id)
        @visits.each do |visit|
          return visit if visit.id == id
        end
        nil
      end

      def find_by_date(date)
        @calculated_days[date]
      end

      def generate_days
        return unless @person
        @calculated_days = {}
        return if @visits.empty?

        begin_date = @visits.first.entry_date
        end_date = @visits.last.exit_date + 180.days
        schengen_days_in_last_180 = 0
        v = 0
        # return if end_date - begin_date > 500
        i = 0
        begin_date.upto(end_date) do | date |
          visit =  @visits[v]

          sd = SchengenDay.new(date)

          #set the country/s
          unless visit.nil?
            set_country(sd,visit)
            if date == visit.exit_date
              v +=1
              visit = @visits[v]
             set_country(sd, visit)
            end
          end
          @calculated_days[sd.the_date]=sd
          schengen_days_in_last_180=calc_schengen_day_count(sd,i,schengen_days_in_last_180)
          i+=1
        end
      end

      def calc_schengen_day_count(sd,i,schengen_days_in_last_180)
          schengen_days_in_last_180 += sd.schengen_day_int
          if i >= 179
            schengen_days_in_last_180 -= calculated_days[i-179].schengen_day_int
          end
          sd.schengen_days_count = schengen_days_in_last_180
          schengen_days_in_last_180
      end

      def total_schengen_days
        calculated_days.reduce(0){|sum,sd| sum += sd.schengen_day_int   }
      end

      def calculated_days
        @calculated_days.values
      end


      private

      def set_country(schengen_day, visit)
        return if visit.nil?
        t = true
        if schengen_day.the_date == visit.entry_date
           schengen_day.entered_country = visit.country 
           t=false
        end
        if schengen_day.the_date == visit.exit_date
           schengen_day.exited_country = visit.country
           t=false
        end
        if t && schengen_day.the_date.between?(visit.entry_date, visit.exit_date)
           schengen_day.stayed_country = visit.country
        end
      end
    end

    class SchengenDay
        attr_accessor :the_date, :entered_country, :stayed_country, :exited_country ,  :schengen_days_count, :notes

        def initialize(date)
          @the_date = date

        end

        def overstay?

        end

        def schengen_day?
          (entered_country && entered_country.schengen?) || (stayed_country && stayed_country.schengen?) || (exited_country && exited_country.schengen?)
        end

        def schengen_day_int 
          schengen_day? ? 1 : 0
        end

        def overstay?
          schengen_days_count > 90
        end

    end
  end
end


   
