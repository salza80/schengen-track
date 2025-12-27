require 'test_helper'

class RegistrationsTest < JavascriptIntegrationTest
  test 'new user Registers' do
    visit new_user_registration_url
    assert_no_text 'New User'
    # Use a unique email for each test run
    unique_email = "test#{Time.now.to_i}@testemail.com"
    fill_in 'First name', with: 'Test'
    fill_in 'Last name', with: 'Signup'
    select 'Australia', from: 'Nationality'
    fill_in 'Email', with: unique_email
    fill_in 'Password', with: 'password'
    fill_in 'Password confirmation', with: 'password'
    click_button 'Sign up'
    assert_text 'Test Signup'
    find('a', text: 'Log out').click
    assert_no_text 'Test Signup'
  end
end
