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
    authorization_url = URI.parse(response.location)
    assert_equal 'https://www.facebook.com/v26.0/dialog/oauth', "#{authorization_url.scheme}://#{authorization_url.host}#{authorization_url.path}"
    assert_equal 'https://graph.facebook.com/v26.0', Devise.omniauth_configs.fetch(:facebook).options.fetch(:client_options).fetch(:site)
    query = Rack::Utils.parse_query(authorization_url.query)
    assert_equal AppConfig.facebook_id, query['client_id']
    assert query['client_id'].present?
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

  test 'Facebook callback refuses a pre-registered email without signing in or copying guest data' do
    account = users(:Sally)
    original_attributes = account.attributes
    guest = create_facebook_guest
    person = guest.people.find_by!(is_primary: true)
    person.visits.create!(entry_date: Date.new(2027, 1, 1), exit_date: Date.new(2027, 1, 5), country: countries(:Germany))
    guest = import_guest_calculation(guest)
    person = guest.people.find_by!(is_primary: true)

    capture_analytics_events do |events|
      assert_no_difference(['User.count', 'Person.count', 'Visit.count']) do
        with_facebook_callback(email: account.email.upcase) { post user_facebook_omniauth_callback_path }
      end
      assert_empty events
    end

    assert_redirected_to new_user_session_path(locale: :en)
    assert_nil request.env['warden'].user(:user)
    assert_nil session['devise.facebook_data']
    assert_equal guest.id, session[:guest_user_id]
    assert_equal original_attributes, account.reload.attributes
    assert_equal guest, person.reload.user
    assert_equal 1, person.visits.count
    follow_redirect!
    assert_response :success
    assert_select '.alert', text: I18n.t('devise.omniauth_callbacks.account_exists')
    assert_select "a[href='#{new_user_password_path(locale: :en)}']"
  end

  test 'Facebook callback creates an account for a new email and copies the guest calculation' do
    guest = create_facebook_guest
    person = guest.people.find_by!(is_primary: true)
    person.visits.create!(entry_date: Date.new(2027, 2, 1), exit_date: Date.new(2027, 2, 5), country: countries(:Germany))
    guest = import_guest_calculation(guest)
    person = guest.people.find_by!(is_primary: true)

    capture_analytics_events do |events|
      assert_difference('User.count', 1) do
        with_facebook_callback(email: 'new-facebook-account@example.com') { post user_facebook_omniauth_callback_path }
      end
      assert_equal ['user_signup'], events.map(&:first)
    end

    assert_redirected_to visits_path(locale: :en)
    account = User.find_by!(email: 'new-facebook-account@example.com')
    assert_equal account, request.env['warden'].user(:user)
    assert_equal 'facebook', account.provider
    assert_equal 'callback-facebook-user', account.uid
    assert_equal 1, account.people.find_by!(is_primary: true).visits.count
    assert_equal guest, person.reload.user
  end

  test 'incomplete Facebook registration keeps only the profile fields needed by the form' do
    with_facebook_callback(email: nil) { post user_facebook_omniauth_callback_path }

    assert_redirected_to new_user_registration_path(locale: :en)
    assert_nil request.env['warden'].user(:user)
    assert_equal({
      'extra' => { 'raw_info' => { 'email' => nil, 'first_name' => 'Facebook', 'last_name' => 'User' } }
    }, session['devise.facebook_data'])
    follow_redirect!
    assert_response :success
    assert_select 'input[name="user[first_name]"][value="Facebook"]'
    assert_select 'input[name="user[last_name]"][value="User"]'
  end

  private

  def create_facebook_guest
    User.create!(
      first_name: 'Guest', last_name: 'Traveller', nationality: countries(:Australia),
      email: 'facebook-callback-guest@example.com', password: 'guest-test-password', guest: true
    )
  end

  def with_facebook_callback(email:)
    previous_test_mode = OmniAuth.config.test_mode
    previous_mock_auth = OmniAuth.config.mock_auth[:facebook]
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:facebook] = OmniAuth::AuthHash.new(
      provider: 'facebook', uid: 'callback-facebook-user',
      info: { email: email, first_name: 'Facebook', last_name: 'User' },
      credentials: { token: 'private-provider-token' },
      extra: { raw_info: { private_profile_field: 'not-needed-for-registration' } }
    )
    yield
  ensure
    OmniAuth.config.test_mode = previous_test_mode
    if previous_mock_auth
      OmniAuth.config.mock_auth[:facebook] = previous_mock_auth
    else
      OmniAuth.config.mock_auth.delete(:facebook)
    end
  end

  def facebook_oauth_form_selector
    'form.facebook-oauth-form[method="post"][data-turbo="false"][action^="/users/auth/facebook"]'
  end
end
