require 'test_helper'
require 'pry'

class VisitTest < ActiveSupport::TestCase
 
  test 'should have the necessary required validators' do
    a = Visit.new
    assert a.invalid?
    assert_equal [:country, :user, :entry_date], a.errors.attribute_names
  end

  test 'no_days including entry and exit date' do
    a =  visits(:two)
    assert_equal 6, a.no_days
  end
  # test 'no_days nil if exit date not specified' do
  #   a =  visits(:three)
  #   assert_equal nil, a.no_days
  # end
  test 'previous_visits scope' do
    a = visits(:three)
    b = a.previous_visits
    assert_equal 2, b.count
    assert_equal '2014-03-10'.to_date, b.first.entry_date
  end

  test 'visit overlap' do

    b = visits(:two)
    assert_not b.date_overlap?

    b.entry_date = '2014-03-21'
    assert b.date_overlap?

    b.entry_date = '2014-03-22'
    b.exit_date = '2014-03-22'
    assert_not b.date_overlap?

    b.exit_date = '2014-03-23'
    assert_not b.date_overlap?

    b.entry_date = '2013-03-22'
    b.exit_date = '2015-03-22'
    assert b.date_overlap?

    a = visits(:one)
    assert_not a.date_overlap?
    a.exit_date = nil
    assert a.date_overlap?

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

    a = visits(:two)
    assert a.valid?
    a.exit_date = '2014-03-23'
    assert a.valid?

    a = visits(:two)
    assert a.valid?
    a.exit_date = '2014-03-22'
    assert a.valid?

  end

  test 'test find by date range' do
    user = users(:Sally)
    a = user.visits.find_by_date('2014-03-20', '2014-03-22')
    assert_equal 2, a.count
    a = user.visits.find_by_date('2010-03-09', nil)
    assert_equal 3, a.count
    a = user.visits.find_by_date('2014-03-27', nil)
    assert_equal 2, a.count
    a = user.visits.find_by_date(nil, '2014-03-27')
    assert_equal 3, a.count
    a = user.visits.find_by_date(nil, '2014-03-26')
    assert_equal 2, a.count
    a = user.visits.find_by_date(nil, nil)
    assert_equal 0, a.count
  end

  test 'test get previous 180 days visits excluding current' do
    a = visits(:two)
    b = a.previous_180_days_visits
    assert_equal 1, b.count
  end

  # ====================
  # Date Range Validation Tests
  # ====================

  test 'should reject entry_date more than 20 years in past' do
    user = users(:Sally)
    visit = user.visits.build(
      country: countries(:Germany),
      entry_date: Date.today - 21.years,
      exit_date: Date.today - 21.years + 5.days
    )
    
    assert visit.invalid?
    assert visit.errors[:entry_date].any?
    assert_match /must be within 20 years/, visit.errors[:entry_date].first
  end

  test 'should reject entry_date more than 20 years in future' do
    user = users(:Sally)
    visit = user.visits.build(
      country: countries(:Germany),
      entry_date: Date.today + 21.years,
      exit_date: Date.today + 21.years + 5.days
    )
    
    assert visit.invalid?
    assert visit.errors[:entry_date].any?
    assert_match /must be within 20 years/, visit.errors[:entry_date].first
  end

  test 'should reject exit_date more than 20 years in past' do
    user = users(:Sally)
    visit = user.visits.build(
      country: countries(:Germany),
      entry_date: Date.today - 21.years,
      exit_date: Date.today - 21.years + 5.days
    )
    
    assert visit.invalid?
    assert visit.errors[:exit_date].any?
    assert_match /must be within 20 years/, visit.errors[:exit_date].first
  end

  test 'should reject exit_date more than 20 years in future' do
    user = users(:Sally)
    visit = user.visits.build(
      country: countries(:Germany),
      entry_date: Date.today + 21.years,
      exit_date: Date.today + 21.years + 5.days
    )
    
    assert visit.invalid?
    assert visit.errors[:exit_date].any?
    assert_match /must be within 20 years/, visit.errors[:exit_date].first
  end

  test 'should accept dates within 20 years' do
    user = users(:Sally)
    visit = user.visits.build(
      country: countries(:Germany),
      entry_date: Date.today - 10.years,
      exit_date: Date.today - 10.years + 5.days
    )
    
    assert visit.valid?
  end

  test 'should accept dates at exactly 20 years boundary' do
    user = users(:Sally)
    visit = user.visits.build(
      country: countries(:Germany),
      entry_date: Date.today - 20.years,
      exit_date: Date.today - 20.years + 5.days
    )
    
    assert visit.valid?
  end

  
end
