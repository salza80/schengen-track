require 'test_helper'
require 'pry'

class CalculatorTest < ActiveSupport::TestCase


  test 'test day calculator days count' do
    person = people(:Test1)
    as =  Schengen::Days::Calculator.new(person)

    assert_equal 645, as.calculated_days.count
    
    assert_equal 102, as.total_schengen_days
 
  end

  test 'schengen day count by day' do
    person = people(:Test1)
    as =  Schengen::Days::Calculator.new(person)

    assert_equal 60, as.calculated_days[59].schengen_days_count
    assert_equal 60, as.calculated_days[60].schengen_days_count

    assert_equal 92, as.find_by_date(Date.new(2014,5,2)).schengen_days_count

    assert_equal 0, as.calculated_days.last.schengen_days_count

    
  end


   test 'test shengen days old calculation day count' do
    person = people(:OldCalcTest)
    as =  Schengen::Days::Calculator.new(person)
   
    assert_equal 1, as.calculated_days.first.schengen_days_count

    assert_equal 30,  as.find_by_date(Date.new(2014,4,29)).schengen_days_count
    assert_equal 30,  as.find_by_date(Date.new(2014,5,5)).schengen_days_count
    assert_equal 85,  as.find_by_date(Date.new(2014,10,19)).schengen_days_count
    assert_equal 1,  as.find_by_date(Date.new(2015,1,8)).schengen_days_count
  end

    test 'no_days_continuous  by day in schengen' do
    person = people(:Test1)
    as =  Schengen::Days::Calculator.new(person)
    a = as.find_visit(visits(:testvisit1).id)

    assert_equal 60, as.find_by_date(Date.new(2014,3,1)).continuous_days_count
    assert_equal 1, as.find_by_date(Date.new(2014,4,1)).continuous_days_count
    assert_equal 30, as.find_by_date(Date.new(2014,4,30)).continuous_days_count
    assert_equal 32, as.find_by_date(Date.new(2014,5,2)).continuous_days_count
    assert_equal 10, as.find_by_date(Date.new(2014,4,10)).continuous_days_count

  end

end
