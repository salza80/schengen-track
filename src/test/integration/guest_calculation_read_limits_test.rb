require 'test_helper'
require 'minitest/mock'

class GuestCalculationReadLimitsTest < ActionDispatch::IntegrationTest
  test 'expensive guest reads share an account quota even when IPs change' do
    source = User.create!(guest: true, email: "read_limit_#{SecureRandom.hex(8)}@example.com", password: 'password123',
                          first_name: 'Guest', last_name: 'Traveler', nationality: countries(:India))
    guest = import_guest_calculation(source)
    previous = GuestCalculatorAbuseControl::READ_LIMIT
    GuestCalculatorAbuseControl.send(:remove_const, :READ_LIMIT)
    GuestCalculatorAbuseControl.const_set(:READ_LIMIT, 2)
    get private_visits_path(locale: :en), env: { 'schengen.client_ip' => '203.0.113.51' }
    assert_response :success
    get private_days_path(locale: :en), env: { 'schengen.client_ip' => '203.0.113.52' }
    assert_response :success
    get max_stay_info_visits_path(locale: :en, format: :json), params: { date: '2027-01-01' },
        env: { 'schengen.client_ip' => '203.0.113.53' }
    assert_response :too_many_requests
    assert_equal 'rate_limited', response.parsed_body.dig('error', 'code')
    assert_equal 3, ApiRateLimit.find_by!(scope: 'guest:web:reads:account', identifier: guest.id.to_s).count
  ensure
    GuestCalculatorAbuseControl.send(:remove_const, :READ_LIMIT)
    GuestCalculatorAbuseControl.const_set(:READ_LIMIT, previous)
  end

  test 'anonymous cached pages never allocate read-limit rows' do
    assert_no_difference('ApiRateLimit.count') do
      get visits_path(locale: :en)
      assert_response :success
      get days_path(locale: :en)
      assert_response :success
    end
  end

  test 'guest calculation reads fail closed when limiter storage fails' do
    source = User.create!(guest: true, email: "read_outage_#{SecureRandom.hex(8)}@example.com", password: 'password123',
                          first_name: 'Guest', last_name: 'Traveler', nationality: countries(:India))
    import_guest_calculation(source)
    raw = Object.new
    raw.define_singleton_method(:exec_params) { |*| raise PG::ConnectionBad, 'outage' }
    ActiveRecord::Base.connection.stub(:raw_connection, raw) { get private_days_path(locale: :en) }
    assert_response :service_unavailable
    assert_equal '60', response.headers['Retry-After']
    assert_includes response.headers['Cache-Control'], 'no-store'
  end

  test 'oversized legacy guests get bounded management pages without deleting history' do
    source = User.create!(guest: true, email: "legacy_history_#{SecureRandom.hex(8)}@example.com", password: 'password123',
                          first_name: 'Guest', last_name: 'Traveler', nationality: countries(:India))
    guest = import_guest_calculation(source)
    person = guest.people.first
    # Represent a guest created before the model storage cap was deployed.
    rows = 501.times.map do |i|
      { person_id: person.id, country_id: countries(:Germany).id,
        entry_date: Date.new(2027, 1, 1) + i * 3, exit_date: Date.new(2027, 1, 2) + i * 3 }
    end
    Visit.insert_all!(rows)
    loaded = 0
    subscriber = ->(_name, _start, _finish, _id, payload) { loaded += payload[:record_count] if payload[:class_name] == 'Visit' }
    assert_no_difference('Visit.count') do
      ActiveSupport::Notifications.subscribed(subscriber, 'instantiation.active_record') { get private_visits_path(locale: :en) }
    end
    assert_response :too_many_requests
    assert_equal 100, loaded
    assert_select 'tr[data-visit-id]', count: 100
    assert_select 'form input[name="_method"][value="delete"]', count: 100
    first_page = css_select('tr[data-visit-id]').map { |row| row['data-visit-id'].to_i }
    assert_select "a[href='#{private_visits_path(locale: :en, before_visit: first_page.last)}']", count: 1
    get private_visits_path(locale: :en, before_visit: first_page.last)
    assert_response :too_many_requests
    second_page = css_select('tr[data-visit-id]').map { |row| row['data-visit-id'].to_i }
    assert_empty first_page & second_page
    get private_days_path(locale: :en)
    assert_response :too_many_requests
    get for_date_visits_path(locale: :en, format: :json), params: { date: '2027-01-01' }
    assert_response :too_many_requests
    assert_equal 501, person.visits.count
    delete visit_path(first_page.first, locale: :en)
    assert_response :redirect
    assert_equal 500, person.visits.count
    get private_visits_path(locale: :en)
    assert_response :success
  end
end
