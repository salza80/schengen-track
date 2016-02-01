require 'test_helper'
require 'pry'

class VisitTest < ActiveSupport::TestCase


  test 'test shengen days count' do
    person = people(:Test1)
    as =  Schengen::Calculator.new(person)
    as.calculate()
    a =as.find_visit(visits(:testvisit1).id)

    assert_equal 60, a.schengen_days

    a = as.find_visit(visits(:testvisit2).id)
    assert_equal 60, a.schengen_days

    a = as.find_visit(visits(:testvisit3).id)
    assert_equal 90, a.schengen_days
    assert_equal 0, a.schengen_overstay_days
    a = as.find_visit(visits(:testvisit4).id)
    assert_equal 92, a.schengen_days
    
    # visits(:testvisit2).destroy
    # a = Visit.find_by(entry_date: '2014-04-30', person: people(:Test1))
    # assert_equal 92, a.schengen_days
    # assert_equal 2, a.schengen_overstay_days
    # visits(:testvisit1).destroy
    # a = visits(:testvisit4)
    # assert_equal 32, a.schengen_days
    # a = visits(:testvisit5)
    # assert_equal 10, a.schengen_days
 
  end

  test 'no_days_continuous in schengen' do
    person = people(:Test1)
    as =  Schengen::Calculator.new(person)
    as.calculate
    a = as.find_visit(visits(:testvisit1).id)
    assert_equal 60, a.no_days_continuous_in_schengen
    a = as.find_visit(visits(:testvisit2).id)
    assert_equal 0, a.no_days_continuous_in_schengen
    a = as.find_visit(visits(:testvisit3).id)
    assert_equal 30, a.no_days_continuous_in_schengen
    a = as.find_visit(visits(:testvisit4).id)
    assert_equal 32, a.no_days_continuous_in_schengen
    a = as.find_visit(visits(:testvisit5).id)
    assert_equal 10, a.no_days_continuous_in_schengen
  end


  test 'test schengen_days count single visit' do
    person = people(:Test2)
    as =  Schengen::Calculator.new(person)
    as.calculate()
    a = as.visits[0] 
    assert_equal 10, a.schengen_days
  end

  test 'schengen_days remaining' do
    person = people(:Test1)
    as =  Schengen::Calculator.new(person)
    as.calculate()
    a = as.find_visit(visits(:testvisit1).id)
    assert_equal 30, a.schengen_days_remaining
  end

  test 'schengen_overstay test' do
    person = people(:Sally)
    as =  Schengen::Calculator.new(person)
    as.calculate()
    a = as.find_visit(visits(:one).id)
    assert_not a.schengen_overstay?

    person = people(:Test1)
    as =  Schengen::Calculator.new(person)
    as.calculate()
    a = as.find_visit(visits(:testvisit4).id)
    assert a.schengen_overstay?
  end

  test 'test shengen days old calculation count' do
    person = people(:OldCalcTest)
    as =  Schengen::Calculator.new(person)
    as.calculate()
    a = as.find_visit(visits(:oldcalc1).id)
    assert_equal 1, a.schengen_days

    a = as.find_visit(visits(:oldcalc2).id)
    assert_equal 30, a.schengen_days
    assert_equal 2, a.visa_entry_count

    a = as.find_visit(visits(:oldcalc3).id)
    assert_equal 30, a.schengen_days
    assert_equal 2, a.visa_entry_count

    a = as.find_visit(visits(:oldcalc4).id)
    assert_equal 60, a.schengen_days

    a = as.find_visit(visits(:oldcalc5).id)
    assert_equal 85, a.schengen_days

    a = as.find_visit(visits(:oldcalc6).id)
    assert_equal 90, a.schengen_days
    assert_equal 0, a.visa_overstay_days

    a = as.find_visit(visits(:oldcalc7).id)
    assert_equal 1, a.schengen_days
  end

  test 'test shengen days when user is from schengen country' do
    person = people(:OldCalcTest)
    as = Schengen::Calculator.new(person)
    as.calculate
    a = as.find_visit(visits(:oldcalc1).id)
    assert_equal 1, a.schengen_days

    a = as.find_visit(visits(:oldcalc2).id)
    assert_equal 30, a.schengen_days

    person = people(:EUPerson)
    as = Schengen::Calculator.new(person)
    as.calculate
    a = as.find_visit(visits(:testeu1).id)
    assert_equal 0, a.schengen_days
  end

  test 'test single entry' do
    person = people(:VisaRequiredPerson)
    as = Schengen::Calculator.new(person)
    as.calculate

    a = as.find_visit(visits(:visaSingleEntry1).id)
    assert_equal 30, a.schengen_days

    a = as.find_visit(visits(:visaSingleEntry2).id)
    assert_equal 30, a.schengen_days

    a = as.find_visit(visits(:visaSingleEntry3).id)
    assert_equal(36, a.schengen_days)
    assert_equal(0, a.schengen_overstay_days)
    assert_equal(6, a.visa_overstay_days)
  end

  test 'test two entry schengen visa' do
    person = people(:VisaRequiredPerson)
    as = Schengen::Calculator.new(person)
    as.calculate
    
    a = as.find_visit(visits(:visaTwoEntry1).id)
    assert_equal 30, a.schengen_days

    a = as.find_visit(visits(:visaTwoEntry2).id)
    assert_equal 30, a.schengen_days

    a = as.find_visit(visits(:visaTwoEntry3).id)
    assert_equal 36, a.schengen_days

    a = as.find_visit(visits(:visaTwoEntry4).id)
    assert_equal(39, a.schengen_days)
    assert_equal(false, a.visa_entry_overstay?)
    assert_equal(0, a.visa_overstay_days)
    assert_equal(0, a.visa_date_overstay_days)

    a = as.find_visit(visits(:visaTwoEntry5).id)
    assert_equal(49, a.schengen_days)
    assert_equal(10, a.visa_overstay_days)
    assert_equal(true, a.visa_entry_overstay?)

    a = as.find_visit(visits(:visaTwoEntry6).id)
    assert_equal(10, a.schengen_days)
    assert_equal(10, a.visa_overstay_days)
    assert_equal(true, a.visa_entry_overstay?)
    assert_equal(10, a.visa_date_overstay_days)

    # v = Visa.new
    # v.start_date = '2012-06-30'
    # v.end_date = '2012-12-30'
    # v.visa_type = 'S'
    # v.no_entries = 0
    # v.person = a.person
    # v.save
    # a.save
    # assert_equal(10, a.schengen_days)
    # assert_equal(0, a.visa_overstay_days)
  end

  test 'big visit schgenen_days' do
    
    person = people(:BigVisits)
    as = Schengen::Calculator.new(person)
    as.calculate

    a = as.find_visit(visits(:bigvisit1).id)
    assert_equal 367, a.schengen_days

    a = as.find_visit(visits(:bigvisit2).id)
    assert_equal 732, a.schengen_days

    a = as.find_visit(visits(:bigvisit3).id)
    assert_equal 1462, a.schengen_days

    a = as.find_visit(visits(:bigvisit4).id)
    assert_equal 1465, a.schengen_days

    # b = b.next_visit
    # assert_equal 1467, b.schengen_days


    # b = b.next_visit
    # assert_equal 1458, b.schengen_days

  end

  test 'no visa visit' do
    person = people(:VisaRequiredPerson)
    as = Schengen::Calculator.new(person)
    as.calculate

    a = as.find_visit(visits(:noVisaVisit1).id)
    assert_equal true, a.visa_required?
    assert_equal false, a.visa_exists?
    assert_equal 7, a.schengen_days
    assert_equal 0, a.schengen_days_remaining
  end
end
