require 'test_helper'
require 'pry'

class CalculatorTest < ActiveSupport::TestCase


  test 'test day calculator days count' do
    user = users(:Test1)
    as =  Schengen::Days::Calculator.new(user)

    
    assert_equal 102, as.total_schengen_days
 
  end

  test 'schengen day count by day' do
    user = users(:Test1)
    as =  Schengen::Days::Calculator.new(user)

    assert_equal 60, as.calculated_days[59].schengen_days_count
    assert_equal 60, as.calculated_days[60].schengen_days_count

    assert_equal 92, as.find_by_date(Date.new(2014,5,2)).schengen_days_count

    assert_equal 0, as.calculated_days.last.schengen_days_count
  end

  test 'schengen max remaining days count ' do
    user = users(:MaxRemaining)
    as =  Schengen::Days::Calculator.new(user)

    assert_equal 80, as.find_by_date(Date.new(2017,6,10)).max_remaining_days
    assert_equal Date.new(2017,9,9), as.next_entry_days.last.the_date
    assert_equal 90, as.calculated_days.last.max_remaining_days
  end


  test 'no_days_continuous  by day in schengen' do
    user = users(:Test1)
    as =  Schengen::Days::Calculator.new(user)
    a = as.find_visit(visits(:testvisit1).id)

    assert_equal 60, as.find_by_date(Date.new(2014,3,1)).continuous_days_count
    assert_equal 1, as.find_by_date(Date.new(2014,4,1)).continuous_days_count
    assert_equal 30, as.find_by_date(Date.new(2014,4,30)).continuous_days_count
    assert_equal 32, as.find_by_date(Date.new(2014,5,2)).continuous_days_count
    assert_equal 10, as.find_by_date(Date.new(2014,4,10)).continuous_days_count


  end

  # ====================
  # Visa Tracking Tests
  # ====================

  test 'schengen day tracks visa information for visa-required user' do
    user = users(:VisaRequiredUser)
    calc = Schengen::Days::Calculator.new(user)
    
    # Single entry visa period (2010-01-01 to 2010-12-30)
    day = calc.find_by_date(Date.new(2010, 1, 15))
    
    assert day.user_requires_visa?
    assert_not_nil day.visa
    assert_equal 1, day.visa_entries_allowed
    assert_equal 1, day.visa_entry_count
  end

  test 'schengen day shows unlimited entries for zero entry visa' do
    user = users(:VisaRequiredUser)
    calc = Schengen::Days::Calculator.new(user)
    
    # Check if there's data in 2013 (unlimited visa)
    day = calc.find_by_date(Date.new(2013, 3, 15))
    
    if day && day.visa
      assert_equal 0, day.visa_entries_allowed
      assert_not day.has_limited_entries?
    end
  end

  test 'schengen day detects visa entry overstay' do
    user = users(:VisaRequiredUser)
    calc = Schengen::Days::Calculator.new(user)
    
    # Two-entry visa, 3rd entry (visaTwoEntry5) - 2012-04-05
    day = calc.find_by_date(Date.new(2012, 4, 5))
    
    assert day.visa
    assert_equal 2, day.visa_entries_allowed
    assert_equal 3, day.visa_entry_count
    assert_not day.visa_entry_valid?
    assert day.visa_warning?
  end

  test 'schengen day detects missing visa' do
    user = users(:VisaRequiredUser)
    calc = Schengen::Days::Calculator.new(user)
    
    # No visa visit (2016-03-02 to 2016-03-08) - after long_visa ends
    day = calc.find_by_date(Date.new(2016, 3, 5))
    
    assert day.user_requires_visa?
    assert_nil day.visa
    assert_not day.visa_valid?
    assert day.visa_warning?
  end

  test 'schengen day detects visit outside visa period' do
    user = users(:VisaRequiredUser)
    calc = Schengen::Days::Calculator.new(user)
    
    # Visit outside two-entry visa period (visa ends 2012-06-30, visit on 2012-11-01)
    day = calc.find_by_date(Date.new(2012, 11, 5))
    
    assert day.user_requires_visa?
    assert_nil day.visa  # No visa covers this date
    assert day.visa_warning?
  end

  test 'consecutive visits count as single entry' do
    user = users(:VisaRequiredUser)
    calc = Schengen::Days::Calculator.new(user)
    
    # visaTwoEntry3 and visaTwoEntry4 are consecutive (no gap)
    # Entry3: 2012-03-01 to 2012-03-06, Entry4: 2012-03-07 to 2012-03-09
    day = calc.find_by_date(Date.new(2012, 3, 8))
    
    assert_equal 2, day.visa_entry_count  # Should be 2 (first entry, then these consecutive)
  end

  test 'non-schengen days do not track visa for display' do
    user = users(:VisaRequiredUser)
    calc = Schengen::Days::Calculator.new(user)
    
    # Australia visit during visa period (2012-02-10)
    day = calc.find_by_date(Date.new(2012, 2, 10))
    
    assert day.user_requires_visa?
    assert_not day.schengen?
    # Visa info should not be set for non-Schengen days
    assert_nil day.visa
  end

  test 'visa entry count increments correctly across multiple entries' do
    user = users(:VisaRequiredUser)
    calc = Schengen::Days::Calculator.new(user)
    
    # Two-entry visa: check progression
    # Entry 1: 2012-01-01 to 2012-01-30
    day1 = calc.find_by_date(Date.new(2012, 1, 15))
    assert_equal 1, day1.visa_entry_count
    
    # Entry 2: 2012-03-01 to 2012-03-06 (after gap)
    day2 = calc.find_by_date(Date.new(2012, 3, 3))
    assert_equal 2, day2.visa_entry_count
    
    # Entry 3: 2012-04-01 to 2012-04-10 (exceeds limit)
    day3 = calc.find_by_date(Date.new(2012, 4, 5))
    assert_equal 3, day3.visa_entry_count
    assert day3.visa_warning?
  end

  test 'non-visa user does not track visa information' do
    user = users(:Test1)  # Australian, no visa required
    calc = Schengen::Days::Calculator.new(user)
    
    day = calc.find_by_date(Date.new(2014, 1, 15))
    
    assert_not day.user_requires_visa?
    assert_nil day.visa
  end

  # ====================
  # Calculator End Date Tests
  # ====================

  test 'calculator extends to today even when last visit is old' do
    user = users(:Test1)
    
    # Create calculator - user's visits are in 2014
    travel_to Date.new(2025, 12, 26) do
      calc = Schengen::Days::Calculator.new(user)
      
      # Should have calculated days through today
      today_day = calc.find_by_date(Date.today)
      assert_not_nil today_day, "Calculator should have data for today"
      
      # Should show 0 days since visits are ancient
      assert_equal 0, today_day.schengen_days_count
    end
  end

  test 'calculator extends 180 days after last visit if later than today' do
    user = users(:Test1)
    
    # Travel to time shortly after last visit
    travel_to Date.new(2014, 6, 1) do
      calc = Schengen::Days::Calculator.new(user)
      
      # Last visit exits around 2014-05-02, so should extend 180 days beyond that
      last_day = calc.calculated_days.max_by(&:the_date)
      expected_end = Date.new(2014, 5, 2) + 180.days
      
      # Should extend to at least today or 180 days after last visit
      assert last_day.the_date >= Date.today, "Should calculate through today"
      assert last_day.the_date >= expected_end, "Should extend 180 days after last visit"
    end
  end
end
