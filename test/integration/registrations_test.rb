require 'test_helper'

class RegistrationsTest < ActionDispatch::IntegrationTest
  test 'new user Registers' do
    visit new_user_registration_url
    assert has_no_content? 'New User'
    within('form.new_user') do
      fill_in 'Email', with: 'smclean17@hotmail.com'
      fill_in 'Password', with: 'password'
      fill_in 'Password confirmation', with: 'password'
      click_button 'Sign up'
    end
    assert has_content? 'New User'
    click_link 'Log out'
    assert has_no_content? 'New User'
  end
end
