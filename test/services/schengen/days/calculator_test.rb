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

    # assert_equal 60, a.schengen_days

    # a = as.find_visit(visits(:testvisit2).id)
    # assert_equal 60, a.schengen_days

    # a = as.find_visit(visits(:testvisit3).id)
    # assert_equal 90, a.schengen_days
    # assert_equal 0, a.schengen_overstay_days
    # a = as.find_visit(visits(:testvisit4).id)
    # assert_equal 92, a.schengen_days
    
  end
end
