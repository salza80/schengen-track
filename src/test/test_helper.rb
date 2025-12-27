ENV['RAILS_ENV'] ||= 'test'
require File.expand_path('../../config/environment', __FILE__)
require 'rails/test_help'
require 'capybara/rails'
require 'active_support/testing/time_helpers'

# Configure Capybara for JavaScript testing
Capybara.default_driver = :rack_test
Capybara.javascript_driver = :selenium_headless

# Configure Selenium to use headless Chrome
Capybara.register_driver :selenium_headless do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument('--headless')
  options.add_argument('--no-sandbox')
  options.add_argument('--disable-dev-shm-usage')
  options.add_argument('--disable-gpu')
  
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
    # Set a desktop viewport size so navigation is visible
    Capybara.page.driver.browser.manage.window.resize_to(1400, 1000)
    super
  end
end
