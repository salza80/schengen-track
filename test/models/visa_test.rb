require 'test_helper'

class VisaTest < ActiveSupport::TestCase

  test 'should have the necessary required validators' do
    a = Visa.new
    assert a.invalid?
    assert_equal [:start_date, :end_date, :person, :visa_type, :no_entries], a.errors.keys
  end


  test 'type must be R or S' do
    a = visas(:single)
    assert a.valid?
    a.visa_type = 'G'
    assert a.invalid?
  end

  test 'type descriptions' do
    a = visas(:single)
    assert a.visa_desc, 'Schengen Visa'
    a.visa_type = 'R'
    assert a.visa_desc, 'Residence Visa/Permit'
  end

  test 'schengen scope' do
    a = Visa.find_schengen

    b = Visa.find_residence
  end


  test 'start date must be less than end date' do
    a = visas(:single)
    assert a.valid?
    a.start_date = '2013-01-01'
    a.end_date = '2012-01-01'
    assert a.invalid?, 'start date is greater than end date'
  end

  test 'find visa for specified entry and exit dates' do
    p = people(:VisaRequiredPerson)
    visa = p.visas.find_schengen_visa(DateTime.new(2011,1,1), DateTime.new(2012,4,4))
    assert_equal nil, visa
    visa  =  p.visas.find_schengen_visa(DateTime.new(2010,1,1), DateTime.new(2010,4,4))
 
    assert_equal DateTime.new(2010,1,1), visa.start_date
    
    visa = p.visas.find_schengen_visa(DateTime.new(2011,2,2), nil)

    assert_equal DateTime.new(2011,1,1), visa.start_date
    assert_equal 0, visa.no_entries
  end
end


