require 'test_helper'

class PasswordRecoverySecurityTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActionMailer::TestHelper

  test 'localized token pages contain only local resources and suppress referrers and caching' do
    token = reset_token_for(users(:Sally))

    I18n.available_locales.each do |locale|
      get edit_user_password_path(locale: locale, reset_password_token: token)

      assert_response :success
      assert_private_recovery_page
      assert_select 'html[lang=?]', locale.to_s
      assert_select 'html[dir=?]', locale.to_sym == :ar ? 'rtl' : 'ltr'
      assert_select 'input[name="user[reset_password_token]"][value=?]', token
      assert_select 'form[action=?]', user_password_path(locale: locale)
    end
  end

  test 'recovery request pages use the same private layout' do
    get new_user_password_path(locale: :en)

    assert_response :success
    assert_private_recovery_page
    assert_select 'input[name="user[email]"]'
    assert_select 'form[action*="auth/facebook"]', count: 0
  end

  test 'mail link resets a password once using a CSRF-protected native form' do
    original_forgery_protection = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    user = users(:Sally)
    get new_user_password_path(locale: :en)
    request_csrf = form_csrf_token

    assert_emails 1 do
      post user_password_path(locale: :en), params: {
        authenticity_token: request_csrf, user: { email: user.email }
      }
    end
    assert_response :redirect
    assert_recovery_headers
    mail = ActionMailer::Base.deliveries.last
    href = Nokogiri::HTML5.fragment(mail.body.decoded).at_css('a')['href']
    token = Rack::Utils.parse_query(URI.parse(href).query).fetch('reset_password_token')
    get URI.parse(href).request_uri
    assert_response :success
    assert_private_recovery_page

    put user_password_path(locale: :en), params: {
      authenticity_token: form_csrf_token,
      user: { reset_password_token: token, password: 'recovered-password', password_confirmation: 'recovered-password' }
    }
    assert_response :redirect
    assert_recovery_headers
    assert user.reload.valid_password?('recovered-password')
    assert_nil user.reset_password_token

    sign_out :user
    get edit_user_password_path(locale: :en, reset_password_token: token)
    put user_password_path(locale: :en), params: {
      authenticity_token: form_csrf_token,
      user: { reset_password_token: token, password: 'replayed-password', password_confirmation: 'replayed-password' }
    }
    assert_response :unprocessable_entity
    assert_private_recovery_page
    assert user.reload.valid_password?('recovered-password')
  ensure
    ActionController::Base.allow_forgery_protection = original_forgery_protection
  end

  test 'password validation failures keep tokens in the private recovery layout' do
    token = reset_token_for(users(:Sally))
    put user_password_path(locale: :en), params: {
      user: { reset_password_token: token, password: 'short', password_confirmation: 'different' }
    }

    assert_response :unprocessable_entity
    assert_private_recovery_page
    assert_select 'input[name="user[reset_password_token]"][value=?]', token
    assert users(:Sally).reload.valid_password?('password')
  end

  test 'null-origin form submissions still require a valid session CSRF token' do
    original_forgery_protection = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    user = users(:Sally)
    token = reset_token_for(user)
    get edit_user_password_path(locale: :en, reset_password_token: token)
    params = { user: { reset_password_token: token, password: 'forged-password', password_confirmation: 'forged-password' } }

    [nil, 'invalid-csrf-token'].each do |csrf|
      assert_raises(ActionController::InvalidAuthenticityToken) do
        put user_password_path(locale: :en), params: params.merge(authenticity_token: csrf), headers: { 'HTTP_ORIGIN' => 'null' }
      end
      assert user.reload.valid_password?('password')
    end
  ensure
    ActionController::Base.allow_forgery_protection = original_forgery_protection
  end

  test 'expired tokens cannot change a password and retain recovery response protections' do
    user = users(:Sally)
    token = reset_token_for(user)
    user.update_column(:reset_password_sent_at, 7.hours.ago)
    put user_password_path(locale: :en), params: {
      user: { reset_password_token: token, password: 'expired-password', password_confirmation: 'expired-password' }
    }

    assert_response :unprocessable_entity
    assert_private_recovery_page
    assert user.reload.valid_password?('password')
  end

  test 'missing tokens and signed-in redirects also suppress referrers' do
    get edit_user_password_path(locale: :en)
    assert_response :redirect
    assert_recovery_headers

    sign_in users(:Sally)
    get edit_user_password_path(locale: :en, reset_password_token: 'private-recovery-token')
    assert_response :redirect
    assert_recovery_headers
    assert_not_includes response.location, 'private-recovery-token'
  end

  private

  def reset_token_for(user)
    raw, digest = Devise.token_generator.generate(User, :reset_password_token)
    user.update_columns(reset_password_token: digest, reset_password_sent_at: Time.current)
    raw
  end

  def form_csrf_token
    Nokogiri::HTML5(response.body).at_css('form input[name="authenticity_token"]')['value']
  end

  def assert_recovery_headers
    assert_equal 'no-referrer', response.headers['Referrer-Policy']
    assert_includes response.headers['Cache-Control'], 'private'
    assert_includes response.headers['Cache-Control'], 'no-store'
    assert_includes response.headers['Content-Security-Policy'], "default-src 'none'"
    assert_includes response.headers['Content-Security-Policy'], "form-action 'self'"
    assert_includes response.headers['Content-Security-Policy'], "frame-ancestors 'none'"
  end

  def assert_private_recovery_page
    assert_recovery_headers
    assert_select 'meta[name="referrer"][content="no-referrer"]'
    assert_select 'script, iframe, link[rel="preconnect"], link[rel="dns-prefetch"]', count: 0
    assert_select '[data-facebook-app-id]', count: 0
    document = Nokogiri::HTML5(response.body)
    document.css('[src], [href], form[action]').each do |element|
      %w[src href action].each do |attribute|
        next unless element[attribute]

        url = URI.join(request.url, element[attribute])
        assert_equal request.host, url.host, "External #{attribute}: #{url}"
        assert_includes %w[http https], url.scheme
      end
    end
  end
end
