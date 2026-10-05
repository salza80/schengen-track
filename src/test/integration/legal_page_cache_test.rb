require 'test_helper'

class LegalPageCacheTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  %w[disclaimer privacy datadeletion].each do |page|
    test "#{page} is cacheable without creating guests or sessions" do
      ["/#{page}", "/fr/#{page}"].each do |path|
        assert_no_difference(['User.count', 'Person.count']) { get path }
        assert_public_page
      end
    end

    test "#{page} excludes signed-in user details and session markup" do
      sign_in users(:Sally)
      get "/#{page}"
      assert_public_page
      assert_not_includes response.body, users(:Sally).full_name
      assert_select '#personDropdown', count: 0
    end
  end

  private

  def assert_public_page
    assert_response :success
    assert_includes response.headers['Cache-Control'], 'public'
    assert_includes response.headers['Cache-Control'], 'max-age=3600'
    assert_nil response.headers['Set-Cookie']
    assert_select 'meta[name="csrf-token"]', count: 0
    assert_select 'input[name="authenticity_token"]', count: 0
    assert_select '#success, #notice', count: 0
  end
end
