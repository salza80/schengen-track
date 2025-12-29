require 'test_helper'

class RegistrationsTest < ActionDispatch::IntegrationTest
  # Use rack_test instead of JavaScript driver for this test
  test 'new user Registers' do
    # Use a unique email for each test run
    unique_email = "test#{Time.now.to_i}@testemail.com"
    
    # Submit registration form
    post user_registration_path, params: {
      user: {
        first_name: 'Test',
        last_name: 'Signup',
        nationality_id: countries(:Australia).id,
        email: unique_email,
        password: 'password',
        password_confirmation: 'password'
      }
    }
    
    # Should redirect after successful registration
    assert_response :redirect
    
    # Verify user was created
    user = User.find_by(email: unique_email)
    assert_not_nil user, "User should be created"
    assert_equal 'Test', user.first_name
    assert_equal 'Signup', user.last_name
    
    # Reload to get associated people
    user.reload
    
    # Verify person was created
    assert_equal 1, user.people.count, "User should have exactly 1 person"
    person = user.people.first
    assert_equal 'Test', person.first_name
    assert_equal 'Signup', person.last_name
    assert person.is_primary
  end
end
