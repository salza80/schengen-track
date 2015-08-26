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

  test 'test get previous 180 days visits excluding current' do
    a = visits(:two)
    b = a.previous_180_days_visits
    assert_equal 1, b.count
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
    assert_equal 0, a.schengen_overstay_days
    a = a.next_visit
    assert_equal 92, a.schengen_days
    visits(:testvisit2).destroy
    a = Visit.find_by(entry_date: '2014-04-30', person: people(:Test1))
    assert_equal 92, a.schengen_days
    assert_equal 2, a.schengen_overstay_days
    visits(:testvisit1).destroy
    a = visits(:testvisit4)
    assert_equal 32, a.schengen_days
    a = visits(:testvisit5)
    assert_equal 10, a.schengen_days
 
  end

  test 'no_days_continuous in schengen' do
    a = visits(:testvisit1)
    assert_equal 60, a.no_days_continuous_in_schengen
    a = a.next_visit
    assert_equal 0, a.no_days_continuous_in_schengen
    a = a.next_visit
    assert_equal 30, a.no_days_continuous_in_schengen
    a = a.next_visit
    assert_equal 32, a.no_days_continuous_in_schengen
    a = a.next_visit
    assert_equal 10, a.no_days_continuous_in_schengen
  end


  test 'test schengen_days count single visit' do
    a = visits(:testsingle)
    a.save
    assert_equal 10, a.schengen_days
  end

  test 'schengen_days remaining' do
    a = visits(:testvisit1)
    a.save
    assert_equal 30, a.schengen_days_remaining
  end

  test 'schengen_overstay test' do
    a = visits(:one)
    a.save
    assert_not a.schengen_overstay?
    a = visits(:testvisit4)
    a.save
    assert a.schengen_overstay?
  end

  test 'test shengen days old calculation count' do
    a = visits(:oldcalc1)
    a.save
    assert_equal 1, a.schengen_days

    a = a.next_visit
    assert_equal 30, a.schengen_days
    assert_equal 2, a.visa_entry_count

    a = a.next_visit
    assert_equal 30, a.schengen_days
    assert_equal 2, a.visa_entry_count

    a = a.next_visit
    assert_equal 60, a.schengen_days

    a = a.next_visit
    assert_equal 85, a.schengen_days

    a = a.next_visit
    assert_equal 90, a.schengen_days
    assert_equal 0, a.visa_overstay_days

    a = a.next_visit
    assert_equal 1, a.schengen_days
  end

  test 'test shengen days when user is from schengen country' do
    a = visits(:oldcalc1)
    a.save
    assert_equal 1, a.schengen_days

    a = a.next_visit
    assert_equal 30, a.schengen_days

    germany = countries(:Germany)
    a.person.nationality = germany
    a.person.save
    a.save
    assert_equal 0, a.schengen_days
  end

  test 'test single entry' do
    a = visits(:visaSingleEntry1)
    a.save
    assert_equal 30, a.schengen_days

    a = a.next_visit
    assert_equal 30, a.schengen_days

    a = a.next_visit
    assert_equal(36, a.schengen_days)
    assert_equal(0, a.schengen_overstay_days)
    assert_equal(6, a.visa_overstay_days)
  end

  test 'test two entry schengen visa' do
    a = visits(:visaTwoEntry1)
    a.save
    assert_equal 30, a.schengen_days

    a = a.next_visit
    assert_equal 30, a.schengen_days

    a = a.next_visit
    assert_equal 36, a.schengen_days

    a = a.next_visit
    assert_equal(39, a.schengen_days)
    assert_equal(false, a.visa_entry_overstay?)
    assert_equal(0, a.visa_overstay_days)
    assert_equal(0, a.visa_date_overstay_days)

    a = a.next_visit
    assert_equal(49, a.schengen_days)
    assert_equal(10, a.visa_overstay_days)
    assert_equal(true, a.visa_entry_overstay?)

    a = a.next_visit
    assert_equal(10, a.schengen_days)
    assert_equal(10, a.visa_overstay_days)
    assert_equal(true, a.visa_entry_overstay?)
    assert_equal(10, a.visa_date_overstay_days)

    v = Visa.new
    v.start_date = '2012-06-30'
    v.end_date = '2012-12-30'
    v.visa_type = 'S'
    v.no_entries = 0
    v.person = a.person
    v.save
    a.save
    assert_equal(10, a.schengen_days)
    assert_equal(0, a.visa_overstay_days)
  end
  test 'big visit schgenen_days' do

    b = visits(:bigvisit1)
    b.save
    assert_equal 367, b.schengen_days

    b =  b.next_visit
    assert_equal 732, b.schengen_days

    b = b.next_visit
    assert_equal 1462, b.schengen_days

    b = b.next_visit
    assert_equal 1465, b.schengen_days

    # b = b.next_visit
    # assert_equal 1467, b.schengen_days


    # b = b.next_visit
    # assert_equal 1458, b.schengen_days

  end

  test 'no visa visit' do
    n = visits(:noVisaVisit1)
    n.save
    assert_equal true, n.visa_required?
    assert_equal false, n.visa_exists?
    assert_equal 7, n.schengen_days
    assert_equal 0, n.schengen_days_remaining
  end

end
