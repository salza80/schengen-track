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
