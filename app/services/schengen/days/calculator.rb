require 'delegate'

module Schengen
  module Days
    # calculates schengen days and continious days in schengen area
    class Calculator
      def initialize(person)
        @person = person
        @visits = @person.visits.to_a
        @calculated_days=[]
        calculate
      end

      def calculate
        return unless @person
        return if @visits.empty?

        generate_days
      end

      def find_visit(id)
        @visits.each do |visit|
          return visit if visit.id == id
        end
        nil
      end

      def generate_days
        return if @visits.empty?
        begin_date = @visits.first.entry_date
        end_date = @visits.last.exit_date
        v = 0
        return if end_date - begin_date > 500
        begin_date.upto(end_date) do | date |
          puts date
          visit =  @visits[v]
          sd = SchengenDay.new(date)

          unless visit.nil?
            set_country(sd,visit)
            if date == visit.exit_date
              v +=1
              visit = @visits[v]
             set_country(sd, visit)
            end
          end
          @calculated_days<<sd
        end



      end

      def total_schengen_days
        calculated_days.reduce(0){|sum,sd| sum += sd.scheng_num  }
      end

      def calculated_days
        @calculated_days
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

        def is_schengen_day
          (entered_country && entered_country.schengen?) || (stayed_country && stayed_country.schengen?) || (exited_country && exited_country.schengen?)
        end

        def scheng_num
          return 1 if is_schengen_day
          0
        end


    end
  end
end


   
