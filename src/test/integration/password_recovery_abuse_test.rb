require 'test_helper'
require 'minitest/mock'

class PasswordRecoveryAbuseTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  test 'normalized recipient cooldown preserves the first link even when clients change' do
    user = users(:Sally)
    assert_emails(1) { recover(user.email) }
    assert_response :see_other
    location, notice = response.location, flash[:notice]
    digest, sent_at = user.reload.reset_password_token, user.reset_password_sent_at
    assert_emails(0) { recover("  #{user.email.upcase}  ", ip: '203.0.113.52') }
    assert_response :see_other
    assert_equal location, response.location
    assert_equal notice, flash[:notice]
    assert_equal digest, user.reload.reset_password_token
    assert_equal sent_at, user.reset_password_sent_at
    assert_recovery_privacy
    travel PasswordRecovery::Request::RECIPIENT_COOLDOWN
    assert_emails(1) { recover(user.email) }
    refute_equal digest, user.reload.reset_password_token
  end

  test 'existing and unknown accounts have the same HTML and JSON confirmation' do
    recover(users(:Sally).email)
    expected = [response.status, response.location, flash[:notice]]
    assert_emails(0) { recover('unknown-recovery@example.invalid') }
    assert_equal expected, [response.status, response.location, flash[:notice]]
    post user_password_path(locale: :en), params: { user: { email: users(:Sally).email } }, as: :json
    expected_json = [response.status, response.parsed_body]
    post user_password_path(locale: :en), params: { user: { email: 'another-unknown@example.invalid' } }, as: :json
    assert_equal expected_json, [response.status, response.parsed_body]
    assert_response :accepted
  end

  test 'client quota is shared across addresses and ignores forged viewer headers' do
    with_constant(:CLIENT_LIMIT, 2) do
      3.times do |i|
        recover("unknown-#{i}@example.invalid", forged: "198.51.100.#{i}")
        assert_response(i < 2 ? :see_other : :too_many_requests)
      end
    end
    assert_operator response.headers['Retry-After'].to_i, :>, 0
    assert_recovery_privacy
  end

  test 'IPv6 privacy addresses share their network bucket' do
    with_constant(:CLIENT_LIMIT, 1) do
      recover('unknown-one@example.invalid', ip: '2001:db8:1:1::1')
      assert_response :see_other
      recover('unknown-two@example.invalid', ip: '2001:db8:1:1::ffff')
      assert_response :too_many_requests
      recover('unknown-three@example.invalid', ip: '2001:db8:1:2::1')
      assert_response :see_other
    end
  end

  test 'localized throttling errors retain the route locale after an exception' do
    with_constant(:CLIENT_LIMIT, 0) do
      post user_password_path(locale: :ar), params: { user: { email: 'unknown@example.invalid' } }
      assert_response :too_many_requests
      assert_equal I18n.t('devise.passwords.rate_limited', locale: :ar).b, response.body.b
    end
  end

  test 'recipient daily quota bounds successful requests after cooldowns expire' do
    with_constant(:RECIPIENT_DAILY_LIMIT, 2) do
      travel_to Time.utc(2026, 11, 6, 12) do
        3.times do |i|
          assert_emails(i < 2 ? 1 : 0) { recover(users(:Sally).email) }
          assert_response :see_other
          travel 11.minutes
        end
      end
    end
  end

  test 'shared delivery quota bounds actual mail without revealing account existence' do
    with_constant(:DELIVERY_LIMIT, 1) do
      assert_emails(1) { recover(users(:Sally).email) }
      expected = [response.status, response.location, flash[:notice]]
      other = users(:VisaRequiredUser)
      original = other.reset_password_token
      assert_emails(0) { recover(other.email) }
      assert_equal expected, [response.status, response.location, flash[:notice]]
      assert_equal original, other.reload.reset_password_token if original
      assert_nil other.reset_password_token unless original
      assert_emails(0) { recover('budget-unknown@example.invalid') }
      assert_equal expected, [response.status, response.location, flash[:notice]]
    end
  end

  test 'limiter outage cannot send mail or replace the current token' do
    user = users(:Sally)
    raw_token, digest = Devise.token_generator.generate(User, :reset_password_token)
    user.update_columns(reset_password_token: digest, reset_password_sent_at: Time.current)
    raw = Object.new
    raw.define_singleton_method(:exec_params) { |*| raise PG::ConnectionBad, 'database outage' }
    assert_emails 0 do
      ActiveRecord::Base.connection.stub(:raw_connection, raw) { recover(user.email) }
    end
    assert_response :service_unavailable
    assert_equal '60', response.headers['Retry-After']
    assert_equal digest, user.reload.reset_password_token
    refute_includes response.body, raw_token
    assert_recovery_privacy
  end

  test 'recipient and network identifiers are blinded and malformed emails send no mail' do
    email, ip = users(:Sally).email, '203.0.113.51'
    recover(email, ip: ip)
    rows = ApiRateLimit.where.not(scope: 'recovery:delivery')
    assert rows.any?
    rows.each do |row|
      assert_match(/\A[0-9a-f]{64}\z/, row.identifier)
      refute_includes row.attributes.values.map(&:to_s).join, email
      refute_includes row.attributes.values.map(&:to_s).join, ip
    end
    assert_emails 0 do
      post user_password_path(locale: :en), params: { user: { email: [email] } }, as: :json
    end
    assert_response :accepted
    filtered = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters).filter('user' => { 'email' => email })
    assert_equal '[FILTERED]', filtered.dig('user', 'email')
  end

  test 'a failed delivery-budget reservation rolls back cooldown so a healthy retry can send' do
    original = RateLimiters::DatabaseFixedWindow.method(:new)
    unavailable = Object.new
    unavailable.define_singleton_method(:call) { raise RateLimiters::DatabaseFixedWindow::Unavailable }
    factory = lambda do |**arguments|
      arguments[:scope] == 'recovery:delivery' ? unavailable : original.call(**arguments)
    end
    assert_emails 0 do
      RateLimiters::DatabaseFixedWindow.stub(:new, factory) { recover(users(:Sally).email) }
    end
    assert_response :service_unavailable
    assert_equal 0, ApiRateLimit.where(scope: 'recovery:cooldown').count
    assert_emails(1) { recover(users(:Sally).email) }
    assert_response :see_other
  end

  private

  def recover(email, ip: '203.0.113.51', forged: '198.51.100.1')
    post user_password_path(locale: :en), params: { user: { email: email } },
         env: { 'schengen.client_ip' => ip }, headers: { 'X-Schengen-Client-Ip' => forged }
  end

  def assert_recovery_privacy
    assert_equal 'no-referrer', response.headers['Referrer-Policy']
    assert_includes response.headers['Cache-Control'], 'no-store'
    assert_includes response.headers['Content-Security-Policy'], "default-src 'none'"
  end

  def with_constant(name, value)
    original = PasswordRecovery::Request.const_get(name)
    PasswordRecovery::Request.send(:remove_const, name)
    PasswordRecovery::Request.const_set(name, value)
    yield
  ensure
    PasswordRecovery::Request.send(:remove_const, name)
    PasswordRecovery::Request.const_set(name, original)
  end
end
