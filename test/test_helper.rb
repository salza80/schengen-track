ENV['RAILS_ENV'] ||= 'test'
require File.expand_path('../../config/environment', __FILE__)
require 'rails/test_help'
require 'capybara/rails'

class ActiveSupport::TestCase
  fixtures :all

  # Add more helper methods to be used by all tests here...

  def login
    @request.env["devise.mapping"] = Devise.mappings[:user]
    sign_in  users(:Sally)
  end
end

class ActionDispatch::IntegrationTest
  # Make the Capybara DSL available in all integration tests
  include Capybara::DSL
  include ActionDispatch::TestProcess
  teardown do
    Capybara.reset!
  end

  def user_login
    visit login_url
    within("//form[@id='login']") do
      fill_in 'Email', with: 'smclean17@gmail.com'
      fill_in 'Password', with: 'password'
      click_button 'Login'
    end
    assert has_content? 'Sally Mclean'
  end
end


