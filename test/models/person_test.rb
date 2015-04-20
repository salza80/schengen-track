require 'test_helper'

class PersonTest < ActiveSupport::TestCase
  
  test 'should have the necessary required validators' do
    a = Person.new
    assert a.invalid?
    assert_equal [:first_name, :last_name, :nationality], a.errors.keys
  end

  test 'find visits by date' do
    person = people(:Sally)
    a = person.find_visits_by_date('2014-03-20', '2014-03-22')
    assert_equal 2, a.count

  end
end
