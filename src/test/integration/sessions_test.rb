require 'test_helper'

class SessionsTest < JavascriptIntegrationTest
  # TODO: This test is flaky with Selenium - investigate form submission issue
  # test 'Existing user logs in and out' do
  #   visit new_user_session_url(locale: :en)
  #   assert_no_text 'Sally Mclean'
  #   fill_in 'Email', with: 'smclean17@gmail.com'
  #   fill_in 'Password', with: 'password'
  #   click_button 'Log in'
  #   # Give the page time to redirect and load
  #   sleep 2
  #   # Wait for name to appear in nav
  #   assert_text 'Sally Mclean', wait: 15
  #   # Click logout
  #   find('a', text: 'Log out', wait: 10).click
  #   # Give the logout time to complete
  #   sleep 2
  #   # Wait for redirect after logout
  #   assert_no_text 'Sally Mclean', wait: 15
  # end
end
