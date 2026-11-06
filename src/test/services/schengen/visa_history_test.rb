require 'test_helper'

module Schengen
  class VisaHistoryTest < ActiveSupport::TestCase
    test 'same-day border records preserve each visit count when the last stop is outside Schengen' do
      person = people(:sally_person)
      person.update!(nationality: countries(:India))
      person.visits.delete_all
      person.visas.delete_all
      person.visas.create!(visa_type: 'S', no_entries: 2, start_date: '2027-01-01', end_date: '2027-12-31')
      records = [:Germany, :Croatia, :Australia].map do |country|
        person.visits.create!(country: countries(country), entry_date: '2027-06-01', exit_date: '2027-06-01')
      end
      history = VisaHistory.new(person)
      records.each { |visit| assert_equal visit.visa_entry_count, history.entry_count_for(visit) }
    end

    test 'duplicate one-day visas use deterministic ID precedence in model and snapshot' do
      person = people(:sally_person)
      person.update!(nationality: countries(:India))
      person.visas.delete_all
      attributes = { visa_type: 'S', no_entries: 1, start_date: '2027-06-01', end_date: '2027-06-01' }
      person.visas.create!(attributes)
      expected = person.visas.create!(attributes.merge(no_entries: 2))
      visit = person.visits.create!(country: countries(:Germany), entry_date: '2027-06-01', exit_date: '2027-06-01')
      assert_equal expected, visit.schengen_visa
      assert_equal expected, VisaHistory.new(person).visa_for_date(visit.entry_date)
    end

    test 'indexed same-day counts match the model for every four-stop border pattern' do
      person = people(:sally_person)
      person.update!(nationality: countries(:India))
      person.visas.delete_all
      person.visas.create!(visa_type: 'S', no_entries: 0, start_date: '2027-01-01', end_date: '2027-12-31')
      [:Germany, :Australia].each do |previous_country|
        [:Germany, :Australia].repeated_permutation(4) do |pattern|
          person.visits.delete_all
          person.visits.create!(country: countries(previous_country), entry_date: '2027-05-31', exit_date: '2027-05-31')
          records = pattern.map do |country|
            person.visits.create!(country: countries(country), entry_date: '2027-06-01', exit_date: '2027-06-01')
          end
          history = VisaHistory.new(person)
          records.each do |visit|
            assert_equal visit.visa_entry_count, history.entry_count_for(visit), "#{previous_country}: #{pattern.inspect}"
          end
        end
      end
    end

    test 'indexed visit counts match standalone calculations including absent visas' do
      person = people(:visa_required_person)
      history = VisaHistory.new(person)
      person.visits.each do |visit|
        expected_visa = visit.schengen_visa
        if expected_visa
          assert_equal expected_visa, history.visa_for_date(visit.entry_date)
        else
          assert_nil history.visa_for_date(visit.entry_date)
        end
        assert_equal visit.visa_entry_count, history.entry_count_for(visit), "Visit #{visit.id}"
      end
    end

    test 'shared visa boundaries and legacy overlaps retain the last applicable visa precedence' do
      person = people(:sally_person)
      person.visas.delete_all
      person.update!(nationality: countries(:India))
      first = person.visas.create!(visa_type: 'S', no_entries: 1, start_date: '2027-01-01', end_date: '2027-06-01')
      second = person.visas.create!(visa_type: 'S', no_entries: 2, start_date: '2027-06-01', end_date: '2027-12-31')
      overlap = person.visas.new(visa_type: 'S', no_entries: 3, start_date: '2027-05-01', end_date: '2027-05-05')
      overlap.save!(validate: false)
      history = VisaHistory.new(person)
      assert_equal first, history.visa_for_date(Date.new(2027, 4, 30))
      assert_equal overlap, history.visa_for_date(Date.new(2027, 5, 3))
      assert_equal first, history.visa_for_date(Date.new(2027, 5, 6))
      assert_equal second, history.visa_for_date(Date.new(2027, 6, 1))
      assert_nil history.visa_for_date(Date.new(2028, 1, 1))
      visits = [Date.new(2027, 4, 20), Date.new(2027, 5, 3), Date.new(2027, 5, 10), Date.new(2027, 5, 20), Date.new(2027, 6, 1)].map do |date|
        person.visits.create!(country: countries(:Germany), entry_date: date, exit_date: date + 1)
      end
      current = visits[-2]
      assert_equal [visits[0].id, visits[2].id], current.previous_visits_on_current_visa.pluck(:id)
      calendar = Days::Calculator.new(person)
      assert_equal second, calendar.find_by_date(visits.last.entry_date).visa
      assert_equal visits.last.visa_entry_count, calendar.find_by_date(visits.last.entry_date).visa_entry_count
    end

    test 'rendering repeated visa fields and CSV uses a bounded number of queries for a long history' do
      person = people(:sally_person)
      person.visits.delete_all
      person.visas.delete_all
      person.update!(nationality: countries(:India))
      person.visas.create!(visa_type: 'S', no_entries: 0, start_date: '2027-01-01', end_date: '2028-12-31')
      rows = 80.times.map do |i|
        { person_id: person.id, country_id: countries(:Germany).id,
          entry_date: Date.new(2027, 1, 1) + i * 3, exit_date: Date.new(2027, 1, 2) + i * 3 }
      end
      Visit.insert_all!(rows)
      person = Person.find(person.id)
      queries = capture_database_queries do
        calc = Calculator.new(person)
        3.times do
          calc.visits.each do |visit|
            visit.visa_entry_overstay?
            visit.visa_entries_allowed
            visit.visa_entry_count
            visit.visa_overstay_days
          end
        end
        assert_equal 80, calc.visits.last.visa_entry_count
        assert_includes calc.to_csv, '80 of Multi'
      end
      selects = queries.select { |sql| sql.match?(/\ASELECT/i) }
      assert_operator selects.length, :<=, 12, selects.join("\n")
    end

    test 'new request snapshots observe new visas without memoizing on the visit model' do
      person = people(:sally_person)
      person.update!(nationality: countries(:India))
      visit = person.visits.create!(country: countries(:Germany), entry_date: '2027-10-01', exit_date: '2027-10-05')
      assert_nil VisaHistory.new(person).visa_for_date(visit.entry_date)
      assert_nil visit.schengen_visa
      visa = person.visas.create!(visa_type: 'S', no_entries: 1, start_date: '2027-01-01', end_date: '2027-12-31')
      assert_equal visa, visit.schengen_visa
      assert_equal visa, VisaHistory.new(person).visa_for_date(visit.entry_date)
    end

    test 'calendar generation does not rebuild the full day array for each day' do
      calculator_class = Class.new(Days::Calculator) do
        attr_reader :day_array_reads
        def calculated_days
          @day_array_reads = (@day_array_reads || 0) + 1
          super
        end
      end
      calc = calculator_class.new(people(:visa_required_person))
      assert_nil calc.day_array_reads
      assert_equal 3, calc.find_by_date(Date.new(2012, 4, 5)).visa_entry_count
    end

    test 'calendar span guard measures days and rejects oversized legacy spans before generation' do
      person = people(:sally_person)
      person.visits.delete_all
      person.visits.new(country: countries(:Germany), entry_date: '1900-01-01', exit_date: '2027-01-01').save!(validate: false)
      assert_raises(Days::Calculator::SpanTooLarge) { Days::Calculator.new(person) }
      assert_operator Days::Calculator::MAX_CALCULATION_DAYS, :<, 15_000
    end
  end
end
