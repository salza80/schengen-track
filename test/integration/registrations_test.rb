require 'test_helper'

class RegistrationsTest < ActionDispatch::IntegrationTest
  test 'new user Registers' do
    visit new_user_registration_url
    assert has_no_content? 'New User'
    within('form.new_user') do
      fill_in 'First name', with: 'Test'
      fill_in 'Last name', with: 'Signup'
      select 'Australia', from: 'Nationality'
      fill_in 'Email', with: 'test@testemail.com'
      fill_in 'Password', with: 'password'
      fill_in 'Password confirmation', with: 'password'
      click_button 'Sign up'
    end
    assert has_content? 'Test Signup'
    click_link 'Log out'
    assert has_no_content? 'Test Signup'
  end
end
