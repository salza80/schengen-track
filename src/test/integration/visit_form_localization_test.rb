require 'test_helper'

class VisitFormLocalizationTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test 'allowance dates use each requested locale while the date shortcut keeps ISO' do
    sign_in users(:Sally)
    I18n.available_locales.each do |locale|
      get max_stay_info_visits_path(locale: locale, format: :json), params: {
        date: '2027-04-12', country_code: 'DE'
      }
      assert_response :success
      assert_equal '2027-07-10', response.parsed_body['exit_date_iso']
      assert_equal I18n.l(Date.new(2027, 7, 10), locale: locale, format: :long), response.parsed_body['exit_date']
    end
  end

  test 'next-visit constraints localize both displayed dates' do
    sign_in users(:Sally)
    [:fr, :ar].each do |locale|
      get max_stay_info_visits_path(locale: locale, format: :json), params: {
        date: '2014-03-11', country_code: 'DE', visit_id: visits(:one).id
      }
      assert_response :success
      assert_equal 'next_visit', response.parsed_body['constraint_type']
      assert_equal '2014-03-21', response.parsed_body['exit_date_iso']
      assert_equal I18n.l(Date.new(2014, 3, 21), locale: locale, format: :long), response.parsed_body['exit_date']
      assert_equal I18n.l(Date.new(2014, 3, 22), locale: locale, format: :long), response.parsed_body['next_entry_date']
    end
  end
end
