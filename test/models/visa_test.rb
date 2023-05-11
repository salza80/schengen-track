require 'test_helper'

class VisaTest < ActiveSupport::TestCase

  test 'should have the necessary required validators' do
    a = Visa.new
    assert a.invalid?
    assert_equal [:user, :start_date, :end_date, :visa_type, :no_entries], a.errors.attribute_names
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


   test 'date overlaping another schengen visa' do
    a = visas(:single)
    assert a.valid?
    a.end_date = '2011-01-01'
    assert a.valid?
    a.end_date = '2011-01-02'
    assert a.invalid?
  end

 test 'start date must be less than end date' do
    a = visas(:single)
    assert a.valid?
    a.start_date = '2013-01-01'
    a.end_date = '2012-01-01'
    assert a.invalid?, 'start date is greater than end date'
  end

  test 'find visa for specified entry and exit dates' do
    u = users(:VisaRequiredUser)
    visa = u.visas.find_schengen_visa(DateTime.new(2011,1,1), DateTime.new(2012,4,4))
    assert_equal  DateTime.new(2011,1,1), visa.start_date
    visa  =  u.visas.find_schengen_visa(DateTime.new(2010,1,1), DateTime.new(2010,4,4))
 
    assert_equal DateTime.new(2010,1,1), visa.start_date
    
    visa = u.visas.find_schengen_visa(DateTime.new(2011,2,2), nil)

    assert_equal DateTime.new(2011,1,1), visa.start_date
    assert_equal 0, visa.no_entries
  end


  test 'test visa dates should not overlap' do
    a = visas(:multi)
    assert a.valid?
    a.start_date = '2010-12-29'
    assert a.invalid?
    a.start_date = '2010-12-30'
    assert a.valid?
    a.end_date = '2012-1-2'
    assert a.invalid?
    a.visa_type = 'R'
    assert a.valid?

  end
end


