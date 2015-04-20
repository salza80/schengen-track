require 'test_helper'

class VisitTest < ActiveSupport::TestCase
 
  test 'should have the necessary required validators' do
    a = Visit.new
    assert a.invalid?
    assert_equal [:country, :person, :entry_date], a.errors.keys
  end

  test 'no_days including entry and exit date' do
    a =  visits(:two)
    assert_equal 6, a.no_days
  end
  test 'no_days nil if exit date not specified' do
    a =  visits(:three)
    assert_equal nil, a.no_days
  end
  test 'previous_visits scope' do
    a = visits(:three)
    b = a.previous_visits
    assert_equal 2, b.count
    assert_equal '2014-03-22'.to_date, b.first.entry_date
  end
  test 'post_visits scope' do
    a = visits(:two)
    b = a.post_visits
    assert_equal 1, b.count
    assert_equal '2014-03-27'.to_date, b.first.entry_date
  end

  test 'entry_date should be greater than exit date' do
    a = visits(:three)
    assert a.valid?
    a.entry_date = '2009-1-2'
    a.exit_date = '2009-1-1'
    assert a.invalid?
  end

  test 'dates can not overlap existing visits by more than one day' do
    a = visits(:one)
    assert a.valid?
    a.exit_date = '2014-3-23'
    assert a.invalid?
  end

  test 'test date range should not overlap existing visits' do
    person = people(:Sally)
    a = Visit.find_by_date(person, '2014-03-20', '2014-03-22')
    assert_equal 2, a.count
    a = Visit.find_by_date(person, '2010-03-09', nil)
  
    assert_equal 3, a.count
    a = Visit.find_by_date(person, '2014-03-27', nil)
    assert_equal 2, a.count
    a = Visit.find_by_date(person, nil, '2014-03-27')
    assert_equal 3, a.count
    a = Visit.find_by_date(person, nil, '2014-03-26')
    assert_equal 2, a.count
  end
end
