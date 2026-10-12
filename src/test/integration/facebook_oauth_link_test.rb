require 'test_helper'

class FacebookOauthLinkTest < ActionDispatch::IntegrationTest
  test 'login opens Facebook OAuth in a new tab with one tap' do
    get new_user_session_path(locale: :en)

    assert_response :success
    assert_select facebook_oauth_link_selector, count: 1
    assert_select 'body', text: /Mobile tip:/, count: 0
  end

  test 'registration opens Facebook OAuth in a new tab with one tap' do
    get new_user_registration_path(locale: :en)

    assert_response :success
    assert_select facebook_oauth_link_selector, count: 1
    assert_select 'body', text: /Mobile tip:/, count: 0
  end

  private

  def facebook_oauth_link_selector
    'a[href^="/users/auth/facebook"][target="_blank"][rel="noopener noreferrer"]'
  end
end
