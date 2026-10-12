require 'test_helper'

class FacebookOauthLinkTest < ActionDispatch::IntegrationTest
  test 'login submits Facebook OAuth in the current tab' do
    get new_user_session_path(locale: :en)

    assert_response :success
    assert_select facebook_oauth_form_selector, count: 1 do
      assert_select 'button[type="submit"]', text: I18n.t('log_in_page.log_in_with_facebook'), count: 1
    end
    assert_select 'a[target="_blank"][href^="/users/auth/facebook"]', count: 0
    assert_select 'body', text: /Mobile tip:/, count: 0
  end

  test 'registration submits Facebook OAuth in the current tab' do
    get new_user_registration_path(locale: :en)

    assert_response :success
    assert_select facebook_oauth_form_selector, count: 1 do
      assert_select 'button[type="submit"]', text: I18n.t('log_in_page.log_in_with_facebook'), count: 1
    end
    assert_select 'a[target="_blank"][href^="/users/auth/facebook"]', count: 0
    assert_select 'body', text: /Mobile tip:/, count: 0
  end

  test 'POST request phase redirects to Facebook' do
    previous_forgery_protection = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    get new_user_session_path(locale: :en)
    form = Nokogiri::HTML(response.body).at_css('form.facebook-oauth-form')
    authenticity_token = form.at_css('input[name="authenticity_token"]')['value']

    post form['action'], params: { authenticity_token: authenticity_token }

    assert_response :redirect
    assert_match %r{\Ahttps://www\.facebook\.com/}, response.location
  ensure
    ActionController::Base.allow_forgery_protection = previous_forgery_protection
  end

  private

  def facebook_oauth_form_selector
    'form.facebook-oauth-form[method="post"][data-turbo="false"][action^="/users/auth/facebook"]'
  end
end
