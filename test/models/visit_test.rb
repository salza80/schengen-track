require 'test_helper'

class VisitTest < ActiveSupport::TestCase
 
  test 'should have the necessary required validators' do
    a = Visit.new
    assert a.invalid?
    assert_equal [:country ,:person, :entry_date], a.errors.keys
  end

  test 'no_days including entry and exit date' do
    a =  visits(:one)
    assert_equal 6, a.no_days
  end
  test 'no_days nil if exit date not specified' do
    a =  visits(:two)
    assert_equal nil, a.no_days
  end

end
