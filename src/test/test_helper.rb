ENV['RAILS_ENV'] ||= 'test'
require File.expand_path('../../config/environment', __FILE__)
require 'rails/test_help'
require 'capybara/rails'
require 'active_support/testing/time_helpers'

# Configure Capybara for JavaScript testing
Capybara.default_driver = :rack_test
Capybara.javascript_driver = :selenium_headless
Capybara.server = :puma, { silent: true }

# Bind to 127.0.0.1 for both local and CI
Capybara.server_host = '127.0.0.1'
if ENV['CI']
  Capybara.server_port = 3000 + ENV['TEST_ENV_NUMBER'].to_i
end

# Configure Selenium to use headless Chrome
Capybara.register_driver :selenium_headless do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument('--headless=new')  # Use new headless mode
  options.add_argument('--no-sandbox')
  options.add_argument('--disable-dev-shm-usage')
  options.add_argument('--disable-gpu')
  options.add_argument('--disable-site-isolation-trials')
  options.add_argument('--disable-web-security')
  options.add_argument('--window-size=1400,1000')
  options.binary = ENV['CHROME_BIN'] if ENV['CHROME_BIN'].present?
  
  # In CI, use container IP address
  if ENV['CI']
    options.add_argument('--disable-setuid-sandbox')
    options.add_argument('--remote-debugging-port=9222')
  end
  
  service_options = {}
  service_options[:path] = ENV['CHROMEDRIVER_PATH'] if ENV['CHROMEDRIVER_PATH'].present?
  service = Selenium::WebDriver::Service.chrome(**service_options)
  
  Capybara::Selenium::Driver.new(app, browser: :chrome, service: service, options: options)
end

class ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers
  fixtures :all

  # Add more helper methods to be used by all tests here...

  def capture_analytics_events
    events = []
    analytics = Analytics::GoogleMeasurementProtocol
    original_track = analytics.method(:track)
    analytics.define_singleton_method(:track) do |event_name, **options|
      events << [event_name, options]
    end

    yield events
  ensure
    analytics&.define_singleton_method(:track, original_track) if original_track
  end

  # Capture every uncached SQL notification emitted by the block. Public-page
  # tests intentionally include schema queries because those also wake Neon.
  def capture_database_queries(&block)
    queries = []
    subscriber = lambda do |_name, _started, _finished, _unique_id, payload|
      queries << payload[:sql] unless payload[:cached]
    end

    ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record', &block)
    queries
  end

  def login
    @request.env["devise.mapping"] = Devise.mappings[:user]
    sign_in  users(:Sally)
  end

  def loginVR
    @request.env["devise.mapping"] = Devise.mappings[:user]
    sign_in  users(:VisaRequiredUser)
  end
end

class ActionDispatch::IntegrationTest
  # Rack 3 exposes Set-Cookie as separate values; inspect all cookie lines.
  def response_cookie_headers
    Array(response.headers['Set-Cookie']).join("\n")
  end

  # Make the Capybara DSL available in all integration tests
  include Capybara::DSL
  include ActionDispatch::TestProcess

  setup do
    # Ensure server is running for each test
    if Capybara.current_driver == Capybara.javascript_driver
      Capybara.current_session.driver.browser
    end
  end

  teardown do
    Capybara.reset_sessions!
    Capybara.use_default_driver
  end

  def user_login
    visit new_user_session_path(locale: :en)
    assert_current_path new_user_session_path(locale: :en), ignore_query: true
    fill_in 'Email', with: 'smclean17@gmail.com'
    fill_in 'Password', with: 'password'
    click_button 'Log in'
    assert_current_path visits_path(locale: :en), ignore_query: true, wait: 10
    assert_text 'Sally Mclean', wait: 10
  end

  def visa_user_login
    visit new_user_session_path(locale: :en)
    assert_current_path new_user_session_path(locale: :en), ignore_query: true
    fill_in 'Email', with: 'smclean17@testvr.com'
    fill_in 'Password', with: 'password'
    click_button 'Log in'
    assert_current_path visits_path(locale: :en), ignore_query: true, wait: 10
    assert_text 'Visa Required', wait: 10
  end
end

# Base class for JavaScript-enabled integration tests
class JavascriptIntegrationTest < ActionDispatch::IntegrationTest
  def setup
    Capybara.current_driver = Capybara.javascript_driver
    # Explicitly set app_host to match the server host
    Capybara.app_host = "http://#{Capybara.server_host}:#{Capybara.server_port}" if Capybara.server_port
    super
  end
  
  def teardown
    Capybara.app_host = nil
    super
  end
end
