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
        records = @person.visas.schengen.order(:id).to_a
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
      records_by_visa = Hash.new { |hash, key| hash[key] = [] }
      previous_schengen, day_counts = {}, Hash.new(0)
      @person.visits.includes(:country).each do |visit|
        visa = visa_for_date(visit.entry_date)
        unless visa
          @visit_entries[visit.id] = visit.schengen? ? 1 : 0
          next
        end
        key = visa.id
        records_by_visa[key] << visit

        next unless visit.schengen?

        prior_schengen = previous_schengen[key]
        day_counts[key] += 1 if !prior_schengen || visit.entry_date - prior_schengen.exit_date > 1
        (@day_entries[key] ||= []) << [visit.entry_date, day_counts[key]]
        previous_schengen[key] = visit
      end

      records_by_visa.each_value { |records| build_visit_entries(records) }
    end

    def build_visit_entries(records)
      count, previous = 0, nil
      records.chunk(&:entry_date).each do |_date, group|
        before_group = previous
        group.each do |visit|
          count += entry_contribution(visit, previous)
          previous = visit
        end
        # The model includes every other record on the current entry date,
        # then appends the current visit. Adjust just its two neighbors rather
        # than rescanning the group for every same-day border record.
        group.each_with_index do |visit, index|
          prior = index.zero? ? before_group : group[index - 1]
          following = group[index + 1]
          without = count - entry_contribution(visit, prior)
          without += entry_contribution(following, prior) - entry_contribution(following, visit) if following
          last_other = index == group.length - 1 ? prior : group.last
          @visit_entries[visit.id] = without + entry_contribution(visit, last_other)
        end
      end
    end

    def entry_contribution(visit, previous)
      return 0 unless visit&.schengen?

      !previous || !previous.schengen? || visit.entry_date - previous.exit_date > 1 ? 1 : 0
    end
  end
end
