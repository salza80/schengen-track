require 'test_helper'
require 'set'

class RollingWindowContractTest < ActiveSupport::TestCase
  # Published examples: https://ec.europa.eu/assets/home/visa-calculator/docs/short_stay_schengen_calculator_user_manual_en.pdf
  test 'the Commission leap-year example counts entry and exit and reaches its limit on August 29' do
    calc = calculate([['2024-01-01', '2024-01-01', :Germany], ['2024-06-01', '2024-09-20', :Germany]])
    assert_equal 15, calc.find_by_date(Date.new(2024, 6, 14)).schengen_days_count
    assert_equal 90, calc.find_by_date(Date.new(2024, 8, 29)).schengen_days_count
    assert_equal 91, calc.find_by_date(Date.new(2024, 8, 30)).schengen_days_count
    assert_equal 90, calc.maximum_stay_from(Date.new(2024, 6, 1))
    assert_equal 0, calc.find_by_date(Date.new(2024, 8, 29)).max_remaining_days
  end

  test 'the Commission planning examples release actual historical days at the correct boundary' do
    calc = calculate([['2024-01-01', '2024-01-10', :Germany], ['2024-03-01', '2024-03-30', :Germany],
                      ['2024-05-01', '2024-06-09', :Germany]], nationality: :India)
    { '2024-06-19' => 20, '2024-08-07' => 20, '2024-08-08' => 50, '2024-09-08' => 90 }.each do |date, expected|
      assert_equal expected, calc.maximum_stay_from(Date.iso8601(date)), date
    end
  end

  test 'leap days and shared country borders are counted once' do
    records = [['2028-02-28', '2028-03-01', :Germany], ['2028-03-01', '2028-03-03', :Australia],
               ['2028-03-03', '2028-03-04', :Germany]]
    calc = calculate(records)
    { '2028-02-28' => 1, '2028-02-29' => 2, '2028-03-01' => 3,
      '2028-03-02' => 3, '2028-03-03' => 4, '2028-03-04' => 5 }.each do |date, expected|
      assert_equal expected, calc.find_by_date(Date.iso8601(date)).schengen_days_count, date
    end
  end

  test 'a shared Schengen border across New Year never doubles the travel day' do
    calc = calculate([['2027-12-31', '2028-01-02', :Germany], ['2028-01-02', '2028-01-04', :Germany]])
    assert_equal 5, calc.total_schengen_days
    assert_equal 5, calc.find_by_date(Date.new(2028, 1, 4)).schengen_days_count
  end

  test 'the 180th historical day drops out exactly once' do
    entry = Date.new(2027, 1, 1)
    calc = calculate([[entry.iso8601, entry.iso8601, :Germany], ['2027-07-10', '2027-07-10', :Australia]])
    assert_equal 1, calc.find_by_date(entry + 179).schengen_days_count
    assert_equal 0, calc.find_by_date(entry + 180).schengen_days_count
  end

  test 'every day of generated compliant mixed-country histories matches an independent set of occupied dates' do
    origin = Date.new(2028, 1, 1)
    8.times do |seed|
      random = Random.new(seed + 650)
      dates = (origin...(origin + 366)).to_a.sample(80, random: random).sort
      occupied = Set.new
      records = dates.map do |date|
        country = random.rand(3).zero? ? :Australia : :Germany
        occupied << date if country == :Germany
        [date.iso8601, date.iso8601, country]
      end
      calc = calculate(records)
      (origin...(origin + 366)).each do |date|
        expected = occupied.count { |day| day.between?(date - 179, date) }
        assert_equal expected, calc.find_by_date(date)&.schengen_days_count || 0, "seed=#{seed}, date=#{date}"
      end
    end
  end

  test 'empty history and freedom of movement retain their separate contracts' do
    calc = calculate([])
    assert_empty calc.calculated_days
    assert_equal 90, calc.maximum_stay_from(Date.new(2027, 4, 1))
    calc = calculate([['2027-01-01', '2027-07-01', :Germany]], nationality: :Germany)
    assert_nil calc.maximum_stay_from(Date.new(2027, 4, 1))
    assert_equal 0, calc.find_by_date(Date.new(2027, 4, 1)).schengen_days_count
  end

  private

  def calculate(rows, nationality: :Australia)
    person = Person.new(nationality: countries(nationality))
    records = rows.map do |entry, exit, country|
      Visit.new(person: person, country: countries(country), entry_date: entry, exit_date: exit)
    end
    Schengen::Days::Calculator.new(person, visits: records)
  end
end
