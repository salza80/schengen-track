require 'test_helper'

class ReferrerPolicyTest < ActionDispatch::IntegrationTest
  test 'public pages send the cross-origin policy without a permissive meta override' do
    I18n.available_locales.each do |locale|
      get visits_path(locale: locale)
      assert_response :success
      assert_equal 'strict-origin-when-cross-origin', response.headers['Referrer-Policy']
      assert_select 'meta[name="referrer"][content="strict-origin-when-cross-origin"]', count: 1
      assert_select 'meta[content="no-referrer-when-downgrade"]', count: 0
    end
  end
end
