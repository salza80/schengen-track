require 'test_helper'

class PersonTest < ActiveSupport::TestCase
  
  test 'should have the necessary required validators' do
    a = Person.new
    assert a.invalid?
    assert_equal [:first_name, :last_name, :nationality], a.errors.keys
  end
end
