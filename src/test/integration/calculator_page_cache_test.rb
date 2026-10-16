require 'test_helper'

class CalculatorPageCacheTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  PUBLIC_PATHS = ['/en/visits', '/en/days?year=2027'].freeze

  test 'cookie-free calculator indexes are public session-free HTML' do
    PUBLIC_PATHS.each do |path|
      reset!
      database_queries = nil
      assert_no_difference(['User.count', 'Person.count', 'Visit.count', 'Visa.count']) do
        database_queries = capture_database_queries do
          get path
        end
      end

      assert_response :success
      assert_empty calculator_record_queries(database_queries),
                   "expected #{path} not to load users, people, trips, or visas"
      assert_includes response.headers['Cache-Control'], 'public'
      assert_includes response.headers['Cache-Control'], 's-maxage=900'
      assert_includes response.headers['Cache-Control'], 'stale-while-revalidate=604800'
      assert_equal 'Cookie', response.headers['Vary']
      assert_nil response.headers['Set-Cookie']
      assert_select 'body[data-public-calculator-page="true"]', count: 1
      assert_select 'meta[name="csrf-token"], input[name="authenticity_token"]', count: 0
      assert_select 'meta[name="robots"][content*="noindex"]', count: 0
      assert_select 'noscript input[type="submit"]', count: 0
      assert_select '#public-user-menu', count: 1
      assert_select '#personDropdown', count: 0

      canonical_path = path.start_with?('/en/days') ? '/days' : '/visits'
      assert_select "link[rel=\"canonical\"][href=\"https://www.example.com#{canonical_path}\"]", count: 1
    end
  end

  test 'unrelated browser cookies do not disable the shared public response' do
    PUBLIC_PATHS.each do |path|
      reset!
      get path, headers: { 'Cookie' => '_ga=analytics-only; cookie_consent=accepted' }

      assert_response :success
      assert_includes response.headers['Cache-Control'], 'public'
      assert_select 'body[data-public-calculator-page="true"]', count: 1
      assert_nil response.headers['Set-Cookie']
    end
  end

  test 'any calculator session indicator forces the private response path' do
    PUBLIC_PATHS.each do |path|
      ['_schengen_track_session=invalid', 'has_calculator_session=', 'has_calculator_session=attacker-value'].each do |cookie|
        reset!
        get path, headers: { 'Cookie' => cookie }

        assert_response :success
        assert_includes response.headers['Cache-Control'], 'private'
        assert_includes response.headers['Cache-Control'], 'no-store'
        assert_equal 'Cookie', response.headers['Vary']
        assert_select 'body[data-public-calculator-page]', count: 0
      end
    end
  end

  test 'public calculator indexes expose accurate search metadata and structured data' do
    get visits_path(locale: :en)

    assert_response :success
    assert_select 'main h1', text: I18n.t('visits.page_title', locale: :en), count: 1
    visits_schema = json_ld_objects.find { |item| item['@type'] == 'WebPage' }
    assert visits_schema
    assert_equal 'UtilitiesApplication', visits_schema.dig('mainEntity', 'applicationCategory')
    assert_equal ['https://www.example.com/', 'https://www.example.com/visits'],
                 visits_schema.dig('breadcrumb', 'itemListElement').map { |item| item['item'] }

    get days_path(locale: :en, year: 2027, month: 4, day: 12)

    assert_response :success
    assert_select '.calendar-public-intro h1', text: I18n.t('days.page_title', locale: :en), count: 1
    assert_select '.calendar-public-intro p', text: I18n.t('days.page_description', locale: :en), count: 1
    schema_types = json_ld_objects.map { |item| item['@type'] }
    assert_includes schema_types, 'WebApplication'
    assert_includes schema_types, 'BreadcrumbList'
    assert_not_includes schema_types, 'FAQPage'
    application_schema = json_ld_objects.find { |item| item['@type'] == 'WebApplication' }
    assert_equal 'UtilitiesApplication', application_schema['applicationCategory']
    breadcrumb_schema = json_ld_objects.find { |item| item['@type'] == 'BreadcrumbList' }
    assert_equal ['https://www.example.com/', 'https://www.example.com/days'],
                 breadcrumb_schema['itemListElement'].map { |item| item['item'] }
  end

  test 'localized calculator breadcrumbs stay within the selected locale' do
    get visits_path(locale: :'pt-BR')

    visits_schema = json_ld_objects.find { |item| item['@type'] == 'WebPage' }
    assert_equal ['https://www.example.com/pt-BR', 'https://www.example.com/pt-BR/visits'],
                 visits_schema.dig('breadcrumb', 'itemListElement').map { |item| item['item'] }

    get days_path(locale: :'pt-BR', year: 2027)

    breadcrumb_schema = json_ld_objects.find { |item| item['@type'] == 'BreadcrumbList' }
    assert_equal ['https://www.example.com/pt-BR', 'https://www.example.com/pt-BR/days'],
                 breadcrumb_schema['itemListElement'].map { |item| item['item'] }
  end

  test 'nationality guest and registered sessions receive private calculator pages' do
    patch calculator_preferences_path(locale: :en), params: {
      nationality_id: countries(:India).id,
      destination: 'trips'
    }
    assert_includes response.headers['Set-Cookie'], 'has_calculator_session=1;'
    get visits_path(locale: :en)
    assert_private_response

    reset!
    guest = User.create!(
      guest: true,
      email: "cache-guest-#{SecureRandom.hex(6)}@example.com",
      password: 'password',
      first_name: 'Cache',
      last_name: 'Guest',
      nationality: countries(:India)
    )
    guest.people.create!(first_name: 'Cache', last_name: 'Guest', nationality: countries(:India), is_primary: true)
    get calculation_link_path(guest.signed_id(purpose: :agent_calculation))
    follow_redirect!
    assert_private_response

    reset!
    sign_in users(:Sally)
    get days_path(locale: :en, year: 2027), headers: { 'Cookie' => 'has_calculator_session=1' }
    assert_private_response
    assert_includes response.body, users(:Sally).first_name
  end

  test 'anonymous nationality guest and registered states render the expected data on both calculator pages' do
    get visits_path(locale: :en)
    assert_calculator_data(visit_rows: 0, travel_days: nil, nationality_step: true)
    get days_path(locale: :en, year: 2027)
    assert_calculator_data(visit_rows: nil, travel_days: 0, nationality_step: true)

    patch calculator_preferences_path(locale: :en), params: {
      nationality_id: countries(:India).id,
      destination: 'trips'
    }
    get visits_path(locale: :en)
    assert_calculator_data(visit_rows: 0, travel_days: nil, nationality_step: false)
    get days_path(locale: :en, year: 2027)
    assert_calculator_data(visit_rows: nil, travel_days: 0, nationality_step: false)

    reset!
    guest = User.create!(
      guest: true,
      email: "cache-render-guest-#{SecureRandom.hex(6)}@example.com",
      password: 'password',
      first_name: 'Cache',
      last_name: 'Guest',
      nationality: countries(:Australia)
    )
    guest_person = guest.people.create!(
      first_name: 'Cache',
      last_name: 'Guest',
      nationality: countries(:Australia),
      is_primary: true
    )
    guest_person.visits.create!(
      entry_date: Date.new(2027, 2, 3),
      exit_date: Date.new(2027, 2, 5),
      country: countries(:Germany)
    )
    get calculation_link_path(guest.signed_id(purpose: :agent_calculation))
    follow_redirect!
    get visits_path(locale: :en)
    assert_calculator_data(visit_rows: 1, travel_days: nil, nationality_step: false)
    get days_path(locale: :en, year: 2027)
    assert_calculator_data(visit_rows: nil, travel_days: 3, nationality_step: false)

    reset!
    post user_session_path(locale: :en), params: {
      user: { email: users(:Sally).email, password: 'password' }
    }
    assert_response :redirect
    assert_includes response.headers['Set-Cookie'], 'has_calculator_session=1;'
    get visits_path(locale: :en)
    assert_calculator_data(visit_rows: 3, travel_days: nil, nationality_step: false)
    get days_path(locale: :en, year: 2014)
    assert_calculator_data(visit_rows: nil, travel_days: 19, nationality_step: false)
  end

  test 'csrf bootstrap creates only a private session token' do
    assert_no_difference(['User.count', 'Person.count', 'Visit.count', 'Visa.count']) do
      get csrf_token_path(locale: :en), as: :json
    end

    assert_response :success
    assert_includes response.headers['Cache-Control'], 'private'
    assert_includes response.headers['Cache-Control'], 'no-store'
    assert_equal 'Cookie', response.headers['Vary']
    assert response.parsed_body['token'].present?
    assert_equal 'authenticity_token', response.parsed_body['param']
    assert_includes response.headers['Set-Cookie'], '_schengen_track_session='
    assert_nil session[:guest_user_id]
    assert_nil session[:calculator_nationality_id]
  end

  private

  def json_ld_objects
    css_select('script[type="application/ld+json"]').filter_map do |script|
      JSON.parse(script.text)
    rescue JSON::ParserError
      nil
    end
  end

  def assert_private_response
    assert_response :success
    assert_includes response.headers['Cache-Control'], 'private'
    assert_includes response.headers['Cache-Control'], 'no-store'
    assert_equal 'Cookie', response.headers['Vary']
    assert_select 'body[data-public-calculator-page]', count: 0
  end

  def assert_calculator_data(visit_rows:, travel_days:, nationality_step:)
    assert_response :success

    if nationality_step
      assert_select '#visitModal[data-nationality-required]', count: 1
      assert_select '.nationality-step-form', count: 1
    else
      assert_private_response
      assert_select '#visitModal[data-nationality-required]', count: 0
      assert_select '.nationality-step-form', count: 0
    end

    assert_select '.clickable-visit-row', count: visit_rows unless visit_rows.nil?
    assert_select '.day-cell.has-travel', count: travel_days unless travel_days.nil?
  end

  def capture_database_queries(&block)
    queries = []
    subscriber = lambda do |_name, _started, _finished, _unique_id, payload|
      queries << payload[:sql] unless payload[:cached]
    end

    ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record', &block)
    queries
  end

  def calculator_record_queries(queries)
    queries.grep(/\b(?:FROM|JOIN)\s+"(?:users|people|visits|visas)"/i)
  end
end
