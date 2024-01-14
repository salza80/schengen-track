require 'test_helper'

class ContinentTest < ActiveSupport::TestCase

  test 'should have the necessary required validators' do
    a = Continent.new
    assert a.invalid?
    assert_equal [:continent_code, :name], a.errors.attribute_names
  end

end
