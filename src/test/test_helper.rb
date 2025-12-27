ENV['RAILS_ENV'] ||= 'test'
require File.expand_path('../../config/environment', __FILE__)
require 'rails/test_help'
require 'capybara/rails'
require 'active_support/testing/time_helpers'

# Configure Capybara for JavaScript testing
Capybara.default_driver = :rack_test
Capybara.javascript_driver = :selenium_headless
Capybara.server = :puma, { Silent: true }
Capybara.server_host = '127.0.0.1'
Capybara.app_host = "http://#{Capybara.server_host}"

# Configure Selenium to use headless Chrome
Capybara.register_driver :selenium_headless do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument('--headless')
  options.add_argument('--no-sandbox')
  options.add_argument('--disable-dev-shm-usage')
  options.add_argument('--disable-gpu')
  options.add_argument('--disable-site-isolation-trials')
  options.add_argument('--window-size=1400,1000')
  
  Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
end

class ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers
  fixtures :all

  # Add more helper methods to be used by all tests here...

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
  # Make the Capybara DSL available in all integration tests
  include Capybara::DSL
  include ActionDispatch::TestProcess

  teardown do
    Capybara.reset!
    Capybara.use_default_driver
  end

  def user_login
    visit new_user_session_path(locale: :en)
    fill_in 'Email', with: 'smclean17@gmail.com'
    fill_in 'Password', with: 'password'
    click_button 'Log in'
    assert_text 'Sally Mclean'
  end

  def visa_user_login
    visit new_user_session_path(locale: :en)
    fill_in 'Email', with: 'smclean17@testvr.com'
    fill_in 'Password', with: 'password'
    click_button 'Log in'
    assert_text 'Visa Required'
  end
end

# Base class for JavaScript-enabled integration tests
class JavascriptIntegrationTest < ActionDispatch::IntegrationTest
  def setup
    Capybara.current_driver = Capybara.javascript_driver
    super
  end
end
