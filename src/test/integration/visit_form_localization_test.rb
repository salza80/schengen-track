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

  test 'entry information follows the requested date and selected country' do
    sign_in users(:Sally)
    get max_stay_info_visits_path(locale: :en, format: :json), params: { date: '2014-03-12', country_code: 'DE' }
    assert_equal 'Days used: 3/90', response.parsed_body.dig('entry_info', 'days_used')
    get max_stay_info_visits_path(locale: :en, format: :json), params: { date: '2014-03-12', country_code: 'AU' }
    assert_nil response.parsed_body['entry_info']
  end

  test 'entry information shows missing or applicable visas in every locale' do
    sign_in users(:VisaRequiredUser)
    I18n.available_locales.each do |locale|
      get max_stay_info_visits_path(locale: locale, format: :json), params: { date: '2027-04-12', country_code: 'DE' }
      assert_equal true, response.parsed_body.dig('entry_info', 'visa_missing')
      assert_equal I18n.t('visits.no_visa_for_date', locale: locale), response.parsed_body.dig('entry_info', 'visa_status')
      get max_stay_info_visits_path(locale: locale, format: :json), params: { date: '2013-04-12', country_code: 'DE' }
      assert_equal false, response.parsed_body.dig('entry_info', 'visa_missing')
      assert_equal I18n.t('days.tooltip.valid_visa', locale: locale), response.parsed_body.dig('entry_info', 'visa_status')
    end
  end

  test 'overstay and waiting warnings stay localized and cannot grant days until the next visit' do
    sign_in users(:BigVisits)
    I18n.available_locales.each do |locale|
      get max_stay_info_visits_path(locale: locale, format: :json), params: { date: '2016-02-10', country_code: 'DE' }
      result = response.parsed_body
      assert_equal false, result['show']
      assert_nil result['exit_date_iso']
      assert_equal I18n.t('days.tooltip.overstay', days: 1373, locale: locale), result.dig('entry_info', 'overstay')

      get max_stay_info_visits_path(locale: locale, format: :json), params: { date: '2016-02-01', country_code: 'DE' }
      result = response.parsed_body
      assert_equal false, result['show']
      assert_equal I18n.t('days.tooltip.wait', days: 148, locale: locale), result.dig('entry_info', 'wait')
    end

    # A trip outside Schengen is limited only by the next recorded trip.
    get max_stay_info_visits_path(locale: :en, format: :json), params: { date: '2016-02-01', country_code: 'AU' }
    assert_equal true, response.parsed_body['show']
    assert_equal 9, response.parsed_body['max_days']
    assert_nil response.parsed_body['entry_info']
  end

  test 'entry information marks exhausted limited visa entries' do
    sign_in users(:VisaRequiredUser)
    get max_stay_info_visits_path(locale: :en, format: :json), params: { date: '2012-04-01', country_code: 'DE' }
    assert_equal true, response.parsed_body.dig('entry_info', 'visa_entries_exceeded')
    assert_equal I18n.t('days.tooltip.entries_exceeded', count: 3, total: 2), response.parsed_body.dig('entry_info', 'visa_entries')
  end

  test 'anonymous JSON visa forms localize nationality and retain prefilled dates' do
    patch calculator_preferences_path(locale: :en), params: { nationality_code: 'IN', destination: 'calendar' }
    I18n.available_locales.each do |locale|
      get new_visa_path(locale: locale, format: :json), params: { start_date: '2027-04-12', end_date: '2027-04-16' }, xhr: true
      assert_response :success
      html = Nokogiri::HTML(response.parsed_body['html'])
      assert_includes html.text, CountryCatalog.find_by_code('IN', locale: locale).name
      assert_equal '2027', html.at_css('#visa_start_date_1i option[selected]')['value']
      assert_equal '16', html.at_css('#visa_end_date_3i option[selected]')['value']
    end
  end
end
