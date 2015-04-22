require 'test_helper'
require 'pry'

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
    assert_equal '2014-03-10'.to_date, b.first.entry_date
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
    a = person.visits.find_by_date('2014-03-20', '2014-03-22')
    assert_equal 2, a.count
    a = person.visits.find_by_date('2010-03-09', nil)
  
    assert_equal 3, a.count
    a = person.visits.find_by_date('2014-03-27', nil)
    assert_equal 2, a.count
    a = person.visits.find_by_date(nil, '2014-03-27')
    assert_equal 3, a.count
    a = person.visits.find_by_date(nil, '2014-03-26')
    assert_equal 2, a.count
    a = person.visits.find_by_date(nil, nil)
    assert_equal 0, a.count
  end

  test 'test get previous 180 days visits including current' do
    a = visits(:two)
    b = a.previous_180_days_visits
    assert_equal 3, b.count
  end

  test 'get next visit' do
    a = visits(:testvisit3)
    n = a.next_visit
    b = visits(:testvisit4)
    assert_equal n.entry_date, b.entry_date
  end

  test 'test shengen days count' do
    a = visits(:testvisit1)
    a.save
    assert_equal 60, a.schengen_days

    a = a.next_visit
    assert_equal 60, a.schengen_days

    a = a.next_visit
    assert_equal 90, a.schengen_days
    a = a.next_visit
    assert_equal 92, a.schengen_days
    visits(:testvisit2).destroy
    a = Visit.find_by(entry_date: '2014-04-30', person: people(:Test1))
    assert_equal 92, a.schengen_days
    visits(:testvisit1).destroy
    a = visits(:testvisit4)
    # a = Visit.find_by(entry_date: '2014-04-30', person: people(:Test1))
    assert_equal 32, a.schengen_days
    a = visits(:testvisit5)
    assert_equal 10, a.schengen_days
 
  end
end
