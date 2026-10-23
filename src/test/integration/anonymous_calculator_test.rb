require 'test_helper'

class AnonymousCalculatorTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test 'calculator no longer emits the legacy country and guest cache cookie' do
    get visits_path(locale: :en)
    assert_not_includes response_cookie_headers, 'cache_country_guest='

    patch calculator_preferences_path(locale: :en), params: {
      nationality_code: 'IN',
      destination: 'trips'
    }
    assert_not_includes response_cookie_headers, 'cache_country_guest='
  end

  test 'calculator session hint is removed when no calculator state remains' do
    get visits_path(locale: :en), headers: { 'Cookie' => 'has_calculator_session=1' }

    assert_match(/has_calculator_session=;.*max-age=0/, response_cookie_headers)
  end

  test 'calculator GET requests do not create persisted records' do
    assert_no_difference(['User.count', 'Person.count', 'Visit.count', 'Visa.count']) do
      get visits_path(locale: :en)
      assert_response :success
      get days_path(locale: :en)
      assert_response :success
      get new_visit_path(locale: :en, format: :js), xhr: true
      assert_response :success
      get max_stay_info_visits_path(locale: :en, format: :json), params: { date: '2027-01-01' }
      assert_response :success
    end
  end

  test 'new trip form posts to an explicit JavaScript endpoint' do
    get new_visit_path(locale: :en, format: :js), xhr: true

    assert_response :success
    assert_match %r{action=\\?"/en/visits\.js\\?"}, response.body
  end

  test 'nationality selection and first trip form use the static country catalogue without SQL' do
    queries = capture_database_queries do
      patch calculator_preferences_path(locale: :en), params: {
        nationality_code: 'IN',
        destination: 'trips'
      }
      get new_visit_path(locale: :en, format: :js), xhr: true
    end

    assert_response :success
    assert_empty country_queries(queries)
    assert_includes response.body, 'visit[country_code]'
    assert_includes response.body, 'value=\\"DE\\"'
  end

  test 'nationality preference survives calendar redirect without creating records' do
    assert_no_difference(['User.count', 'Person.count']) do
      patch calculator_preferences_path(locale: :en), params: {
        nationality_code: 'IN',
        destination: 'calendar',
        year: 2027,
        month: 4,
        day: 12
      }
    end

    assert_redirected_to days_path(locale: :en, year: '2027', month: '4', day: '12')
    follow_redirect!
    assert_equal '1', cookies[:has_calculator_session]
    assert_select 'select[name="nationality_code"]', count: 0

    get visits_path(locale: :en)
    assert_select 'select[name="nationality_code"] option[selected]', text: countries(:India).localized_name
    assert_select 'select[name="nationality_code"] option[value=""]', count: 0
  end

  test 'first valid trip creates one guest and selected primary person atomically' do
    patch calculator_preferences_path(locale: :en), params: {
      nationality_code: 'IN',
      destination: 'trips'
    }

    assert_difference(['User.count', 'Person.count', 'Visit.count'], 1) do
      post visits_path(locale: :en), params: {
        visit: { entry_date: '2027-01-10', exit_date: '2027-01-15', country_id: countries(:Germany).id }
      }
    end

    guest = User.where(guest: true).order(:id).last
    assert_equal countries(:India), guest.nationality
    assert_equal countries(:India), guest.people.find_by!(is_primary: true).nationality
    assert_redirected_to visits_path(locale: :en)
  end

  test 'valid trip without an explicit nationality does not create calculator records' do
    assert_no_difference(['User.count', 'Person.count', 'Visit.count']) do
      post visits_path(locale: :en), params: {
        visit: { entry_date: '2027-01-10', exit_date: '2027-01-15', country_id: countries(:Germany).id }
      }
    end

    assert_redirected_to visits_path(locale: :en, open: 'trip')
    assert_nil session[:guest_user_id]
  end

  test 'stale anonymous trip form returns JavaScript that reopens the nationality step' do
    assert_no_difference(['User.count', 'Person.count', 'Visit.count']) do
      post visits_path(locale: :en, format: :js), params: {
        visit: { entry_date: '2027-01-10', exit_date: '2027-01-15', country_id: countries(:Germany).id }
      }, xhr: true
    end

    assert_response :success
    assert_includes response.body, visits_path(locale: :en, open: 'trip')
  end

  test 'first valid visa creates one guest and visa' do
    patch calculator_preferences_path(locale: :en), params: {
      nationality_code: 'IN',
      destination: 'trips'
    }

    assert_difference(['User.count', 'Person.count', 'Visa.count'], 1) do
      post visas_path(locale: :en), params: {
        visa: { start_date: '2027-01-01', end_date: '2027-06-01', no_entries: 1 }
      }
    end

    assert_redirected_to visits_path(locale: :en)
    assert User.where(guest: true).order(:id).last.people.find_by!(is_primary: true).visas.exists?
  end

  test 'valid visa without an explicit nationality does not create calculator records' do
    assert_no_difference(['User.count', 'Person.count', 'Visa.count']) do
      post visas_path(locale: :en), params: {
        visa: { start_date: '2027-01-01', end_date: '2027-06-01', no_entries: 1 }
      }
    end

    assert_redirected_to visits_path(locale: :en)
    assert_nil session[:guest_user_id]
  end

  test 'invalid first save rolls back guest and person' do
    patch calculator_preferences_path(locale: :en), params: {
      nationality_code: 'IN',
      destination: 'trips'
    }

    assert_no_difference(['User.count', 'Person.count', 'Visit.count']) do
      post visits_path(locale: :en, format: :js), params: {
        visit: { entry_date: '2027-01-10', exit_date: '2027-01-15', country_id: '' }
      }, xhr: true
    end

    assert_response :success
    assert_includes response.body, 'prohibited this visit from being saved'
  end

  test 'invalid preference leaves prior selection unchanged' do
    patch calculator_preferences_path(locale: :en), params: {
      nationality_code: 'IN',
      destination: 'trips'
    }
    patch calculator_preferences_path(locale: :en), params: {
      nationality_code: 'not-a-country',
      destination: 'trips'
    }
    follow_redirect!

    assert_select 'select[name="nationality_code"] option[selected]', text: countries(:India).localized_name
  end

  test 'fresh Trips page uses unique IDs for the page and modal nationality controls' do
    get visits_path(locale: :en)

    assert_select '#calculator_nationality_selector', count: 1
    assert_select '#calculator_nationality_selector[required] option:first-child[value=""]', text: I18n.t('common.select_nationality')
    assert_select '#calculator_nationality_selector option[selected]', count: 0
    assert_select 'label[for="calculator_nationality_selector"]', count: 1
    assert_select '#calculator_nationality_step', count: 1
    assert_select '#calculator_nationality_step[required] option:first-child[value=""]', text: I18n.t('common.select_nationality')
    assert_select '#calculator_nationality_step option[selected]', count: 0
    assert_select 'label[for="calculator_nationality_step"]', count: 1
    assert_select 'form[data-csrf-bootstrap-url="/en/csrf_token"]', count: 2
    assert_select 'input[name="authenticity_token"]', count: 0
    assert_select '[data-action="add-visa"]', count: 0
    assert_select '#nationality_code, #destination', count: 0
    assert_select '.guest-registration-card', count: 0
  end

  test 'persisted guests and signed-in users skip the nationality step' do
    sign_in users(:Sally)
    get visits_path(locale: :en, open: 'trip'), headers: { 'Cookie' => 'has_calculator_session=1' }
    assert_select '#visitModal[data-nationality-required]', count: 0
    assert_select '.nationality-step-form', count: 0
    assert_select '.guest-registration-card', count: 0
    sign_out :user

    guest = User.create!(
      guest: true,
      email: "step-guest-#{SecureRandom.hex(6)}@example.com",
      password: 'password',
      first_name: 'Guest',
      last_name: 'User',
      nationality: countries(:India)
    )
    get calculation_link_path(guest.signed_id(purpose: :agent_calculation))
    get visits_path(locale: :en, open: 'trip')

    assert_select '#visitModal[data-nationality-required]', count: 0
    assert_select '.nationality-step-form', count: 0
    assert_select '.guest-registration-card', count: 1
    assert_select ".guest-registration-card a[href='#{new_user_registration_path(locale: :en)}']", count: 1

    get days_path(locale: :en)
    assert_select '.guest-registration-card', count: 0
  end

  test 'anonymous requests cannot access saved trips' do
    trip = visits(:one)
    [[:get, visit_path(trip, locale: :en, format: :json)],
     [:get, edit_visit_path(trip, locale: :en, format: :json)],
     [:patch, visit_path(trip, locale: :en, format: :json)],
     [:delete, visit_path(trip, locale: :en, format: :json)]].each do |method, path|
      reset!
      queries = capture_database_queries { public_send(method, path) }
      assert_response :not_found
      assert_empty queries
    end

    get edit_visit_path(trip, locale: :en, format: :js), xhr: true
    assert_response :success
    assert_includes response.body, 'window.location.href'
    assert Visit.exists?(trip.id)
  end

  test 'anonymous requests cannot access saved visas' do
    visa = visas(:one)
    [[:get, edit_visa_path(visa, locale: :en, format: :js)],
     [:patch, visa_path(visa, locale: :en, format: :json)],
     [:delete, visa_path(visa, locale: :en, format: :json)]].each do |method, path|
      reset!
      queries = capture_database_queries do
        assert_raises(ActiveRecord::RecordNotFound) { public_send(method, path) }
      end
      assert_empty queries
    end
    assert Visa.exists?(visa.id)
  end

  private

  def country_queries(queries)
    queries.grep(/\b(?:FROM|JOIN)\s+"(?:countries|continents)"/i)
  end
end
