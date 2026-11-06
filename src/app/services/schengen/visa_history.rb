# frozen_string_literal: true

module Schengen
  # Request-local visa lookups and entry counts, shared by Trips and Calendar.
  # Never memoize these derived values on a persistent Active Record instance.
  class VisaHistory
    def initialize(person)
      @person = person
      @visa_by_date = {}
    end

    def visa_for_date(date)
      return nil unless date

      @visa_by_date.fetch(date) do
        finish = visas.bsearch_index { |visa| visa.start_date > date } || visas.length
        @visa_by_date[date] = if finish.zero? || @maximum_end_dates[finish - 1] < date
                                nil
                              else
                                # Normally the last candidate wins immediately.
                                # Retain correct precedence for legacy overlaps.
                                (finish - 1).downto(0).lazy.map { |i| visas[i] }.find { |visa| visa.end_date >= date }
                              end
      end
    end

    def entry_count_for(visit)
      build_entries
      @visit_entries.fetch(visit.id) { visit.schengen? ? 1 : 0 }
    end

    def entry_count_on(date, visa)
      build_entries
      timeline = @day_entries.fetch(visa.id, [])
      finish = timeline.bsearch_index { |entry_date, _count| entry_date > date } || timeline.length
      finish.zero? ? 0 : timeline[finish - 1][1]
    end

    private

    def visas
      @visas ||= begin
        records = @person.visas.schengen.to_a
        maximum = nil
        @maximum_end_dates = records.map do |visa|
          maximum = [maximum, visa.end_date].compact.max
        end
        records
      end
    end

    def build_entries
      return if @visit_entries

      @visit_entries, @day_entries = {}, {}
      previous, previous_schengen, counts, day_counts = {}, {}, Hash.new(0), Hash.new(0)
      @person.visits.includes(:country).each do |visit|
        visa = visa_for_date(visit.entry_date)
        unless visa
          @visit_entries[visit.id] = visit.schengen? ? 1 : 0
          next
        end
        key = visa.id
        prior = previous[key]
        if visit.schengen? && (!prior || !prior.schengen? || visit.entry_date - prior.exit_date > 1)
          counts[key] += 1
        end
        @visit_entries[visit.id] = counts[key]
        previous[key] = visit

        next unless visit.schengen?

        prior_schengen = previous_schengen[key]
        day_counts[key] += 1 if !prior_schengen || visit.entry_date - prior_schengen.exit_date > 1
        (@day_entries[key] ||= []) << [visit.entry_date, day_counts[key]]
        previous_schengen[key] = visit
      end
    end
  end
end
