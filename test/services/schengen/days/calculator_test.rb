require 'test_helper'
require 'pry'

class CalculatorTest < ActiveSupport::TestCase


  test 'test day calculator days count' do
    person = people(:Test1)
    as =  Schengen::Days::Calculator.new(person)

    assert_equal 465, as.calculated_days.count
    
    assert_equal 102, as.total_schengen_days
 
  end
end
