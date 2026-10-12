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
    query = Rack::Utils.parse_query(URI.parse(response.location).query)
    if AppConfig.facebook_web_login_workaround?
      assert_equal 'joey', query['sdk']
    else
      assert_nil query['sdk']
    end
    assert_equal 'code', query['response_type']
    assert_equal 'page', query['display']
    assert_equal 'http://localhost:3000/users/auth/facebook/callback', query['redirect_uri']
    assert_equal 'email,public_profile', query['scope']
    assert query['state'].present?
    assert_equal query['state'], session['omniauth.state']
  ensure
    ActionController::Base.allow_forgery_protection = previous_forgery_protection
  end

  test 'POST request phase rejects missing CSRF token' do
    post user_facebook_omniauth_authorize_path

    assert_response :redirect
    assert_redirected_to new_user_session_path(locale: :en)
    assert_match(/authenticity/i, flash[:alert])
  end

  test 'callback rejects an unrecognized OAuth state' do
    previous_forgery_protection = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    get new_user_session_path(locale: :en)
    form = Nokogiri::HTML(response.body).at_css('form.facebook-oauth-form')
    post form['action'], params: { authenticity_token: form.at_css('input[name="authenticity_token"]')['value'] }
    assert_response :redirect

    get '/users/auth/facebook/callback', params: { code: 'invalid-code', state: 'invalid-state' }

    assert_redirected_to new_user_session_path(locale: :en)
    assert_match(/csrf/i, flash[:alert])
  ensure
    ActionController::Base.allow_forgery_protection = previous_forgery_protection
  end

  private

  def facebook_oauth_form_selector
    'form.facebook-oauth-form[method="post"][data-turbo="false"][action^="/users/auth/facebook"]'
  end
end
