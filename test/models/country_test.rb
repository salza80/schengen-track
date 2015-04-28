require 'test_helper'

class CountryTest < ActiveSupport::TestCase

  test 'should have the necessary required validators' do
    a = Country.new
    assert a.invalid?
    assert_equal [:country_code, :name, :continent], a.errors.keys
  end

  test 'should return false to schengen? if no schengen start_date' do
    a = countries(:Australia)
    assert_equal false, a.schengen?
  end

  test 'should return false if schengen start_date is in the future' do
    a = countries(:Croatia)
    assert_equal false, a.schengen?
  end

  test 'should return true if schengen start_date is less that date passed in' do
    a = countries(:Croatia)
    assert_equal true, a.schengen?(Date.new(2017, 1, 1))
    assert_equal true, true
  end

  test 'should return true to is_schengen if start_date is earlier than current date' do
    a = countries(:Germany)
    assert_equal true, a.schengen?
  end
end
