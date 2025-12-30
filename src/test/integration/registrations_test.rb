require 'test_helper'

class RegistrationsTest < ActionDispatch::IntegrationTest
  test 'new user registers and inherits guest user data' do
    # Create a guest user (simulating the automatic guest user creation)
    guest = User.create!(
      first_name: 'Guest',
      last_name: 'User',
      nationality_id: countries(:India).id,
      email: "guest_#{SecureRandom.hex(8)}@example.com",
      password: 'password',
      guest: true
    )
    guest_person = guest.people.first
    
    # Add some visits to the guest person
    visit1 = guest_person.visits.create!(
      entry_date: Date.new(2024, 1, 1),
      exit_date: Date.new(2024, 1, 10),
      country: countries(:Germany)
    )
    visit2 = guest_person.visits.create!(
      entry_date: Date.new(2024, 2, 1),
      exit_date: Date.new(2024, 2, 5),
      country: countries(:Croatia)
    )
    
    # Use a unique email for the new user
    unique_email = "test#{SecureRandom.hex(8)}@testemail.com"
    
    # Create the new user programmatically (simulating what the controller does)
    new_user = User.create!(
      first_name: 'Test',
      last_name: 'Signup',
      nationality_id: countries(:Australia).id,
      email: unique_email,
      password: 'password123',
      password_confirmation: 'password123'
    )
    
    # Call copy_from to copy guest data (simulating what registrations#create does)
    new_user.copy_from(guest)
    new_user.save!
    
    # Verify new user was created
    assert_not_nil new_user, "New user should be created"
    assert_equal 'Test', new_user.first_name
    assert_equal 'Signup', new_user.last_name
    assert_equal false, new_user.guest
    
    # Reload to get associated people
    new_user.reload
    
    # Verify person was created
    assert_equal 1, new_user.people.count, "New user should have exactly 1 person"
    new_person = new_user.people.first
    assert_equal 'Test', new_person.first_name
    assert_equal 'Signup', new_person.last_name
    assert new_person.is_primary, "Person should be primary"
    
    # Verify visits were copied from guest user
    assert_equal 2, new_person.visits.count, "New person should have 2 visits copied from guest"
    copied_visits = new_person.visits.order(:entry_date)
    
    assert_equal Date.new(2024, 1, 1), copied_visits.first.entry_date
    assert_equal Date.new(2024, 1, 10), copied_visits.first.exit_date
    assert_equal countries(:Germany).id, copied_visits.first.country_id
    
    assert_equal Date.new(2024, 2, 1), copied_visits.second.entry_date
    assert_equal Date.new(2024, 2, 5), copied_visits.second.exit_date
    assert_equal countries(:Croatia).id, copied_visits.second.country_id
    
    # Verify the visits are copies (different IDs)
    assert_not_equal visit1.id, copied_visits.first.id, "Visit should be a copy, not the same record"
    assert_not_equal visit2.id, copied_visits.second.id, "Visit should be a copy, not the same record"
  end

  test 'guest user flow: visits page -> add data -> register -> data persists' do
    # Step 1: Visit the visits page as a guest (this triggers guest user creation)
    get visits_path
    assert_response :success
    
    # The application should have created a guest user in the session
    # We can verify by checking if there's a guest user in the response or session
    # For this test, we'll work with the session that was established
    
    # Step 2: Verify we can access the page (guest user was auto-created)
    assert_select 'body' # Basic check that page loaded
    
    # Step 3: Add a visit via POST request (as the guest user would)
    post visits_path, params: {
      visit: {
        entry_date: '2024-03-01',
        exit_date: '2024-03-10',
        country_id: countries(:Germany).id
      }
    }
    
    # Should redirect after creating visit
    assert_response :redirect
    follow_redirect!
    assert_response :success
    
    # Step 4: Add a visa via POST request
    post visas_path, params: {
      visa: {
        start_date: '2024-01-01',
        end_date: '2024-12-31',
        no_entries: 2,
        visa_type: 'S'
      }
    }
    
    assert_response :redirect
    follow_redirect!
    assert_response :success
    
    # Step 5: Get the guest user that was created (from session/database)
    # In the actual app flow, this is stored in session[:guest_user_id]
    # For testing, we'll find the guest user that was just created
    guest_user = User.where(guest: true).order(created_at: :desc).first
    assert_not_nil guest_user, "Guest user should have been created"
    
    guest_person = guest_user.people.first
    assert_not_nil guest_person, "Guest person should exist"
    
    # Verify the guest has the data we added
    assert_equal 1, guest_person.visits.count, "Guest should have 1 visit"
    assert_equal 1, guest_person.visas.count, "Guest should have 1 visa"
    
    # Step 6: Register a new account
    unique_email = "integration_test_#{SecureRandom.hex(8)}@example.com"
    post user_registration_path, params: {
      user: {
        first_name: 'Integration',
        last_name: 'Test',
        nationality_id: countries(:Australia).id,
        email: unique_email,
        password: 'password123',
        password_confirmation: 'password123'
      }
    }
    
    # Should redirect after registration
    assert_response :redirect
    
    # Step 7: Find the newly registered user
    new_user = User.find_by(email: unique_email)
    assert_not_nil new_user, "New user should be created"
    assert_equal false, new_user.guest, "New user should not be a guest"
    
    # Step 8: Verify the new user has the data from the guest user
    new_person = new_user.people.first
    assert_not_nil new_person, "New user should have a person"
    
    # This is the key assertion: visits and visas should have been copied
    assert_equal 1, new_person.visits.count, "New user should have the guest's visit"
    assert_equal 1, new_person.visas.count, "New user should have the guest's visa"
    
    # Verify the visit data
    copied_visit = new_person.visits.first
    assert_equal Date.new(2024, 3, 1), copied_visit.entry_date
    assert_equal Date.new(2024, 3, 10), copied_visit.exit_date
    assert_equal countries(:Germany).id, copied_visit.country_id
    
    # Verify the visa data
    copied_visa = new_person.visas.first
    assert_equal Date.new(2024, 1, 1), copied_visa.start_date
    assert_equal Date.new(2024, 12, 31), copied_visa.end_date
    assert_equal 2, copied_visa.no_entries
    
    # Step 9: Log in as the new user and verify we can access their data
    post user_session_path, params: {
      user: { email: unique_email, password: 'password123' }
    }
    assert_response :redirect
    
    # Step 10: Visit the visits page and verify the data is still there
    get visits_path
    assert_response :success
    
    # Verify the visa exists in the database for the new user
    new_user.reload
    assert_equal 1, new_user.people.first.visas.count, "Visa should exist in the database for the new user"
    # The visa would be visible on the visits page calendar view
  end

  test 'user with no people gets one created automatically on login' do
    # Create a user manually without triggering the after_create callback
    user = User.new(
      first_name: 'Test',
      last_name: 'NoPerson',
      nationality_id: countries(:Australia).id,
      email: "no_person_#{SecureRandom.hex(8)}@example.com",
      password: 'password123',
      password_confirmation: 'password123',
      guest: false
    )
    
    # Skip the callback that creates the primary person
    user.save!(validate: false)
    user.people.delete_all # Ensure no people exist
    user.reload
    
    # Verify user has no people
    assert_equal 0, user.people.count, "User should have no people initially"
    
    # Log in as this user
    post user_session_path, params: {
      user: { email: user.email, password: 'password123' }
    }
    assert_response :redirect
    follow_redirect!
    
    # Navigate to the visits page (this will trigger current_user_or_guest_user)
    get visits_path
    assert_response :success
    
    # Reload user and verify a person was created
    user.reload
    assert_equal 1, user.people.count, "User should have 1 person after login"
    
    # Verify the person has correct data
    person = user.people.first
    assert_not_nil person, "Person should exist"
    assert_equal 'Test', person.first_name
    assert_equal 'NoPerson', person.last_name
    assert_equal countries(:Australia).id, person.nationality_id
    assert person.is_primary, "Person should be marked as primary"
    
    # Verify we can access the person
    assert_equal person, user.people.find_by(is_primary: true)
  end
end
