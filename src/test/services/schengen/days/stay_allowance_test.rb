require 'test_helper'

class StayAllowanceTest < ActiveSupport::TestCase
  test 'recorded future days do not replenish the allowance for a stay' do
    calc = calculator_for([['2027-01-01', '2027-01-30'], ['2027-02-10', '2027-03-11'],
                           ['2027-04-01', '2027-04-30']])
    assert_equal 30, calc.maximum_stay_from(Date.new(2027, 4, 1))
    assert_equal 29, calc.find_by_date(Date.new(2027, 4, 1)).max_remaining_days
    assert_equal 1, calc.find_by_date(Date.new(2027, 4, 29)).max_remaining_days
    assert_equal 90, calc.find_by_date(Date.new(2027, 4, 30)).schengen_days_count
    assert_equal 0, calc.find_by_date(Date.new(2027, 4, 30)).max_remaining_days
  end

  test 'the last available day is included in a new stay' do
    calc = calculator_for([['2027-01-01', '2027-03-30'], ['2027-04-01', '2027-04-01']])
    assert_equal 1, calc.maximum_stay_from(Date.new(2027, 4, 1))
    assert_equal 0, calc.maximum_stay_from(Date.new(2027, 4, 2))
    assert_equal 0, calc.find_by_date(Date.new(2027, 4, 1)).max_remaining_days
  end

  test 'only actual historical days leaving the 180 day window release allowance' do
    calc = calculator_for([['2027-01-01', '2027-01-30'], ['2027-05-01', '2027-05-30']])
    assert_equal 60, calc.maximum_stay_from(Date.new(2027, 6, 1))
    calc = calculator_for([['2027-01-01', '2027-03-31']])
    assert_equal 0, calc.maximum_stay_from(Date.new(2027, 6, 29))
    assert_equal 90, calc.maximum_stay_from(Date.new(2027, 6, 30))
  end

  test 'a waiting period ending produces one reentry option' do
    calc = calculator_for([['2027-01-01', '2027-04-01']])
    dates = calc.next_entry_days.map(&:the_date)
    assert_predicate dates, :any?
    assert_equal dates.uniq, dates
  end

  test 'allowance agrees with counting occupied days in each candidate rolling window' do
    entry = Date.new(2027, 6, 1)
    [0, 1, 30, 60, 89, 90].product([0, 1, 2, 3]).each do |count, seed|
      history = ((entry - 179)...entry).to_a.sample(count, random: Random.new(seed + 427))
      trips = history.sort.map { |date| [date.iso8601, date.iso8601] }
      calc = calculator_for(trips + [[entry.iso8601, (entry + 29).iso8601]])
      expected = (0...90).take_while do |offset|
        finish = entry + offset
        occupied = history + (entry..finish).to_a
        occupied.count { |date| date.between?(finish - 179, finish) } <= 90
      end.length
      assert_equal expected, calc.maximum_stay_from(entry), "history=#{count}, seed=#{seed}"
      assert_equal [expected - 1, 0].max, calc.find_by_date(entry).max_remaining_days,
                   "remaining after entry: history=#{count}, seed=#{seed}"
    end
  end

  private

  def calculator_for(dates)
    person = Person.new(nationality: countries(:Australia))
    records = dates.map do |entry, exit|
      Visit.new(person: person, country: countries(:Germany), entry_date: entry, exit_date: exit)
    end
    Schengen::Days::Calculator.new(person, visits: records)
  end
end
