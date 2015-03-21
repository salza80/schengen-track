require 'test_helper'

class CountryTest < ActiveSupport::TestCase


  test 'should have the necessary required validators' do
    a = Country.new
    assert a.invalid?
    assert_equal [:code, :name], a.errors.keys
  end

  test 'should return false to is_schengen if no schengen start_date' do
    a = counties(:Australia)
    asset_equal false, a.is_schengen
  end

  test 'should return false to is_schengen if schengen start_date is in the future' do
    a = counties(:Croatia)
    asset_equal false, a.is_schengen
  end
  test 'should return true to is_schengen if schengen start_date is less that date passed in' do
    a = counties(:Croatia)
    asset_equal true, a.is_schengen('1/1/2017'.to_d)
  end

  test 'should return true to is_schengen if start_date is earlier than current date' do
    a = counties(:Germany)
    asset_equal true, a.is_schengen
  end
end
