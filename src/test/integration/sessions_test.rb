require 'test_helper'

class SessionsTest < ActionDispatch::IntegrationTest
  test 'Existing user logs in and out' do
    visit new_user_session_url(locale: :en)
    assert has_no_content? 'Sally Mclean'
    within('form#login') do
      fill_in 'Email', with: 'smclean17@gmail.com'
      fill_in 'Password', with: 'password'
      click_button 'Log in'
    end
    assert has_content? 'Sally Mclean'
    click_link 'Log out'
    assert has_no_content? 'Sally Mclean'
  end
end
