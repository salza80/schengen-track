require 'test_helper'

class VisitTest < ActiveSupport::TestCase
 
  test 'should have the necessary required validators' do
    a = Visit.new
    assert a.invalid?
    assert_equal [:country ,:person, :entry_date], a.errors.keys
  end

end
