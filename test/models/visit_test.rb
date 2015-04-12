require 'test_helper'

class VisitTest < ActiveSupport::TestCase
 
  test 'should have the necessary required validators' do
    a = Visit.new
    assert a.invalid?
    assert_equal [:country, :person, :entry_date], a.errors.keys
  end

  test 'no_days including entry and exit date' do
    a =  visits(:one)
    assert_equal 6, a.no_days
  end
  test 'no_days nil if exit date not specified' do
    a =  visits(:two)
    assert_equal nil, a.no_days
  end
  test 'previous_visits scope' do
    a = visits(:two)
    b = a.previous_visits
    assert_equal 1, b.count
    assert_equal '2014-03-22'.to_date, b.first.entry_date
  end
  test 'post_visits scope' do
    a = visits(:one)
    b = a.post_visits
    assert_equal 1, b.count
    assert_equal '2014-03-27'.to_date, b.first.entry_date
  end
end
