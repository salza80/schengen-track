require 'test_helper'

class VisitTest < ActiveSupport::TestCase
 
  test 'should have the necessary required validators' do
    a = Person.new
    assert a.invalid?
    assert_equal [:entry_date, :person, :country], a.errors.keys
  end

end
