require 'test_helper'

class PrivateCalculatorRoutingTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test 'language links retain only calendar presentation parameters on public and private routes' do
    sign_in users(:Sally)
    get session_header_path(locale: :en)
    [days_path(locale: :en), private_days_path(locale: :en)].each do |path|
      get path, params: { year: 2027, month: 4, day: 12, tracking: 'discard-me' }
      assert_response :success
      document = Nokogiri::HTML(response.body)
      links = document.css('.language-select option, .language-links-seo a')
      links.each do |link|
        destination = URI.parse(link['value'] || link['href'])
        assert_equal path.sub('/en/', '/fr/'), destination.path if link['lang'] == 'fr'
        assert_equal({ 'year' => '2027', 'month' => '4', 'day' => '12' },
                     Rack::Utils.parse_query(destination.query))
      end
    end
  end

  test 'public calculators ignore even a real signed session and preserve it for private access' do
    original_forgery_protection = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    sign_in users(:Sally)
    person = people(:sally_person)
    person.update!(first_name: 'PrivateOnlyCalculatorName')
    get session_header_path(locale: :en) # Finish Devise's test-only deferred sign-in.
    [visits_path(locale: :en), days_path(locale: :en)].each do |path|
      queries = capture_database_queries { get path, headers: { 'Cookie' => 'has_calculator_session=1' } }
      assert_response :success
      assert_empty queries
      assert_includes response.headers['Cache-Control'], 'public'
      assert_nil response.headers['Set-Cookie']
      assert_select 'body[data-public-calculator-page="true"]', count: 1
      assert_not_includes response.body, person.first_name
      assert_select 'a[href^="/en/my/"]', minimum: 1
    end

    get private_visits_path(locale: :en)
    assert_response :success
    assert_includes response.body, person.first_name
    assert_includes response.headers['Cache-Control'], 'private'
    assert_includes response.headers['Cache-Control'], 'no-store'
    assert_select 'meta[name="csrf-token"]', count: 1
    assert_select 'a[href="/en/my/days"]', minimum: 1
  ensure
    ActionController::Base.allow_forgery_protection = original_forgery_protection
  end

  test 'private calculators reject unvalidated cookies before computation and preserve presentation parameters' do
    Schengen::Calculator.stub(:new, ->(*) { flunk 'calculator must not run' }) do
      queries = capture_database_queries do
        get private_visits_path(locale: :fr), headers: { 'Cookie' => 'has_calculator_session=1; _schengen_track_session=invalid' }
      end
      assert_empty queries
      assert_redirected_to visits_path(locale: :fr)
      assert_includes response.headers['Cache-Control'], 'private'
      assert_includes response.headers['Cache-Control'], 'no-store'
    end
    Schengen::Days::Calculator.stub(:new, ->(*) { flunk 'calendar must not run' }) do
      get private_days_path(locale: :ar), params: { year: 2027, month: 3, host: 'evil.example' }
      assert_redirected_to days_path(locale: :ar, year: 2027, month: 3)
      assert_includes response.headers['Cache-Control'], 'no-store'
    end
  end

  test 'header continuation requires validated user or nationality state and keeps flash for the private destination' do
    get session_header_path(locale: :en, calculator_page: 'visits'), headers: { 'Cookie' => 'has_calculator_session=1' }
    assert_response :no_content

    sign_in users(:Sally)
    post set_current_person_path(people(:sally_person_alt), locale: :en)
    get session_header_path(locale: :en, calculator_page: 'visits')
    assert_response :success
    assert_equal({ 'calculator_path' => private_visits_path(locale: :en) }, response.parsed_body)
    get private_visits_path(locale: :en)
    assert_response :success
    assert_includes response.body, 'Switched to Sally Alternative'

    reset!
    assert_no_difference(['User.count', 'Person.count']) do
      patch calculator_preferences_path(locale: :fr), params: { nationality_code: 'IN', destination: 'calendar' }
      assert_redirected_to private_days_path(locale: :fr)
      get session_header_path(locale: :fr, calculator_page: 'days')
      assert_equal({ 'calculator_path' => private_days_path(locale: :fr) }, response.parsed_body)
      get private_days_path(locale: :fr)
      assert_response :success
      assert_includes response.headers['Cache-Control'], 'private'
    end
  end

  test 'public CSV links move to the private export without exposing session data on the public route' do
    sign_in users(:Sally)
    get visits_path(locale: :en, format: :csv)
    assert_redirected_to private_visits_path(locale: :en, format: :csv)
    assert_includes response.headers['Cache-Control'], 'no-store'
    follow_redirect!
    assert_response :success
    assert_includes response.headers['Content-Disposition'], 'attachment'
    assert_operator response.body.lines.length, :>, 1
    assert_includes response.headers['Cache-Control'], 'private'
  end
end
