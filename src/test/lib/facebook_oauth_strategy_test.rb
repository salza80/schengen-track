require 'test_helper'
require 'faraday/adapter/test'

# Exercise the configured provider and its HTTP client without OmniAuth's mock
# callback mode, real credentials, or network access.
class FacebookOauthStrategyTest < Minitest::Test
  GRAPH_URL = 'https://graph.facebook.com/v26.0'.freeze
  JSON_HEADERS = { 'Content-Type' => 'application/json' }.freeze
  CLIENT_ID = 'transport-test-client'.freeze
  CLIENT_SECRET = 'transport-test-secret'.freeze
  ACCESS_TOKEN = 'transport-test-token'.freeze

  def setup
    @previous_failure = OmniAuth.config.on_failure
    @previous_test_mode = OmniAuth.config.test_mode
    OmniAuth.config.test_mode = false
    OmniAuth.config.on_failure = ->(_env) { [401, {}, []] }
    @stubs = Faraday::Adapter::Test::Stubs.new
    @requests = []
  end

  def teardown
    OmniAuth.config.on_failure = @previous_failure
    OmniAuth.config.test_mode = @previous_test_mode
  end

  def test_authorization_code_exchange_and_profile_lookup
    stub_token
    stub_profile

    env, status = callback

    assert_equal 200, status
    auth = env.fetch('omniauth.auth')
    assert_equal 'transport-test-user', auth.uid
    assert_equal 'transport@example.com', auth.info.email
    assert_equal ["#{GRAPH_URL}/oauth/access_token", "#{GRAPH_URL}/me"], @requests.map { |request| request[:url].split('?').first }
    token_request, profile_request = @requests
    assert_equal 'test-authorization-code', token_request[:body]['code']
    assert_equal 'authorization_code', token_request[:body]['grant_type']
    assert_equal 'http://localhost:3000/users/auth/facebook/callback', token_request[:body]['redirect_uri']
    assert_equal "Basic #{Base64.strict_encode64("#{CLIENT_ID}:#{CLIENT_SECRET}")}", token_request[:authorization]
    assert_equal "OAuth #{ACCESS_TOKEN}", profile_request[:authorization]
    assert_equal 'email,first_name,last_name', profile_request[:params]['fields']
    expected_proof = OpenSSL::HMAC.hexdigest('SHA256', CLIENT_SECRET, ACCESS_TOKEN)
    assert_equal expected_proof, profile_request[:params]['appsecret_proof']
  end

  def test_token_redirect_on_the_same_origin_preserves_the_exchange
    stub_request(:post, 'oauth/access_token', status: 307, headers: { 'Location' => "#{GRAPH_URL}/redirected-token" })
    stub_token(path: 'redirected-token')
    stub_profile

    env, status = callback

    assert_equal 200, status
    assert_equal 'transport-test-user', env.fetch('omniauth.auth').uid
    assert_equal %w[/v26.0/oauth/access_token /v26.0/redirected-token /v26.0/me], request_paths
    assert_equal @requests.first[:body], @requests.second[:body]
    assert_equal @requests.first[:authorization], @requests.second[:authorization]
  end

  def test_profile_redirect_on_the_same_origin_preserves_authentication
    stub_token
    stub_request(:get, 'me', status: 302, headers: { 'Location' => "#{GRAPH_URL}/redirected-me" })
    stub_profile(path: 'redirected-me')

    env, status = callback

    assert_equal 200, status
    assert_equal 'transport-test-user', env.fetch('omniauth.auth').uid
    assert_equal %w[/v26.0/oauth/access_token /v26.0/me /v26.0/redirected-me], request_paths
    assert_equal "OAuth #{ACCESS_TOKEN}", @requests.last[:authorization]
    assert_equal @requests.second[:params], @requests.last[:params]
  end

  def test_token_redirect_to_another_host_is_blocked_before_sending_credentials
    stub_request(:post, 'oauth/access_token', status: 307, headers: { 'Location' => 'https://other.facebook.com/token' })

    assert_callback_failure('cross_origin_redirect_blocked')
    assert_equal ['/v26.0/oauth/access_token'], request_paths
  end

  def test_profile_redirect_to_another_host_is_blocked_before_sending_the_token
    stub_token
    stub_request(:get, 'me', status: 302, headers: { 'Location' => 'https://other.facebook.com/me' })

    assert_callback_failure('cross_origin_redirect_blocked')
    assert_equal %w[/v26.0/oauth/access_token /v26.0/me], request_paths
  end

  def test_expired_authorization_code_fails_without_requesting_a_profile
    stub_request(:post, 'oauth/access_token', status: 400, body: { error: 'invalid_grant', error_description: 'Expired code' })

    assert_callback_failure('invalid_grant')
    assert_equal ['/v26.0/oauth/access_token'], request_paths
  end

  def test_rejected_profile_token_does_not_authenticate
    stub_token
    stub_request(:get, 'me', status: 401, body: { error: 'invalid_token', error_description: 'Expired token' })

    assert_callback_failure('invalid_token')
    assert_equal %w[/v26.0/oauth/access_token /v26.0/me], request_paths
  end

  def test_invalid_state_never_contacts_the_provider
    env, status = callback(state: 'wrong-state')

    assert_equal 401, status
    assert_equal :csrf_detected, env.fetch('omniauth.error.type')
    assert_nil env['omniauth.auth']
    assert_empty @requests
  end

  private

  def stub_token(path: 'oauth/access_token')
    stub_request(:post, path, body: { access_token: ACCESS_TOKEN, token_type: 'bearer', expires_in: 3600 })
  end

  def stub_profile(path: 'me')
    stub_request(:get, path, body: { id: 'transport-test-user', email: 'transport@example.com', first_name: 'Transport', last_name: 'Test' })
  end

  def stub_request(method, path, status: 200, headers: JSON_HEADERS, body: {})
    @stubs.public_send(method, "#{GRAPH_URL}/#{path}") do |request|
      @requests << {
        url: request.url.to_s,
        body: Rack::Utils.parse_query(request.request_body),
        params: Rack::Utils.parse_query(request.url.query),
        authorization: request.request_headers['Authorization']
      }
      [status, headers, body.to_json]
    end
  end

  def callback(state: 'test-state')
    options = Devise.omniauth_configs.fetch(:facebook).options.deep_dup
    options[:callback_path] = '/users/auth/facebook/callback'
    options[:client_options][:connection_build] = lambda do |builder|
      builder.request(:url_encoded)
      builder.adapter(:test, @stubs)
    end
    strategy = OmniAuth::Strategies::Facebook.new(->(_env) { [200, {}, []] }, CLIENT_ID, CLIENT_SECRET, options)
    env = Rack::MockRequest.env_for("http://localhost:3000/users/auth/facebook/callback?code=test-authorization-code&state=#{state}")
    env['rack.session'] = { 'omniauth.state' => 'test-state' }
    status, = strategy.call!(env)
    @stubs.verify_stubbed_calls
    [env, status]
  end

  def assert_callback_failure(code)
    env, status = callback

    assert_equal 401, status
    assert_equal :invalid_credentials, env.fetch('omniauth.error.type')
    assert_equal code, env.fetch('omniauth.error').code
    assert_nil env['omniauth.auth']
    assert @requests.all? { |request| URI.parse(request[:url]).host == 'graph.facebook.com' }
  end

  def request_paths
    @requests.map { |request| URI.parse(request[:url]).path }
  end
end
