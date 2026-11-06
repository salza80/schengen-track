require 'test_helper'
require 'minitest/mock'

class GuestAllocationLimitsTest < ActionDispatch::IntegrationTest
  test 'fresh sessions and forged viewer headers share the trusted IP creation quota' do
    with_constant(GuestCalculatorAbuseControl, :WRITE_LIMIT, 2) do
      3.times do |index|
        reset!
        select_nationality
        assert_difference('User.count', index < 2 ? 1 : 0) do
          post visits_path(locale: :en, format: :js), params: { visit: trip }, xhr: true,
               env: { 'schengen.client_ip' => '203.0.113.50' },
               headers: { 'X-Schengen-Client-Ip' => "198.51.100.#{index}" }
        end
        assert_response(index < 2 ? :success : :too_many_requests)
      end
    end
    assert_equal 'rate_limited', response.parsed_body.dig('error', 'code')
    assert_operator response.headers['Retry-After'].to_i, :>, 0
    assert_includes response.headers['Cache-Control'], 'no-store'
    assert_equal ['203.0.113.50'], ApiRateLimit.where(scope: 'guest:web:allocations:ip').distinct.pluck(:identifier)
  end

  test 'guest continuation shares a quota across trip visa and traveler creation and changing IPs' do
    guest = import_guest_calculation(source)
    with_constant(GuestCalculatorAbuseControl, :WRITE_LIMIT, 2) do
      post visits_path(locale: :en, format: :js), params: { visit: trip }, xhr: true, env: { 'schengen.client_ip' => '203.0.113.51' }
      assert_response :success
      post visas_path(locale: :en, format: :js), params: { visa: visa }, xhr: true, env: { 'schengen.client_ip' => '203.0.113.52' }
      assert_response :success
      assert_no_difference('Person.count') do
        post people_path(locale: :en), params: { person: { first_name: 'Blocked' } }, env: { 'schengen.client_ip' => '203.0.113.53' }
      end
      assert_response :too_many_requests
    end
    assert_equal 1, guest.people.count
  end

  test 'capacity counts both kinds of record across every traveler and can be freed by deletion' do
    guest = import_guest_calculation(source)
    person = guest.people.first
    other = guest.people.create!(first_name: 'Other', nationality: countries(:India))
    other.visas.create!(visa)
    with_constant(GuestCalculations::Capacity, :MAX_RECORDS, 1) do
      assert_no_difference('Visit.count') do
        post visits_path(locale: :en, format: :js), params: { visit: trip }, xhr: true
      end
      assert_response :too_many_requests
      assert_equal 'calculator_capacity_reached', response.parsed_body.dig('error', 'code')
      other.visas.first.destroy!
      post visits_path(locale: :en, format: :js), params: { visit: trip }, xhr: true
      assert_response :success
      assert_equal 1, person.visits.count
    end
  end

  test 'traveler capacity is enforced on the server' do
    guest = import_guest_calculation(source)
    with_constant(GuestCalculations::Capacity, :MAX_PEOPLE, 1) do
      assert_no_difference('Person.count') do
        post people_path(locale: :en), params: { person: { first_name: 'Blocked' } }
      end
      assert_response :too_many_requests
    end
    assert_equal 1, guest.people.count
  end

  test 'missing limiter storage rejects first save without allocating a guest' do
    select_nationality
    raw = Object.new
    raw.define_singleton_method(:exec_params) { |*| raise PG::UndefinedTable, 'missing table' }
    assert_no_difference(['User.count', 'Person.count', 'Visit.count', 'Visa.count']) do
      ActiveRecord::Base.connection.stub(:raw_connection, raw) do
        post visits_path(locale: :en, format: :js), params: { visit: trip }, xhr: true
      end
    end
    assert_response :service_unavailable
    assert_equal '60', response.headers['Retry-After']
    assert_equal 'service_unavailable', response.parsed_body.dig('error', 'code')
  end

  test 'registered travelers retain normal saves without consuming guest quotas' do
    post user_session_path(locale: :en), params: { user: { email: users(:Sally).email, password: 'password' } }
    with_constant(GuestCalculatorAbuseControl, :WRITE_LIMIT, 0) do
      with_constant(GuestCalculations::Capacity, :MAX_RECORDS, 0) do
        assert_difference('Visit.count', 1) do
          post visits_path(locale: :en, format: :js), params: { visit: trip }, xhr: true
        end
        assert_response :success
      end
    end
    assert_equal 0, ApiRateLimit.where(scope: 'guest:web:allocations:ip').count
  end

  test 'claim throttling occurs before copying records or consuming the source link' do
    original = source
    with_constant(GuestCalculatorAbuseControl, :WRITE_LIMIT, 0) do
      assert_no_difference(['User.count', 'Person.count']) do
        post claim_calculation_path, params: { token: original.signed_id(purpose: :agent_calculation) }
      end
      assert_response :too_many_requests
      assert_nil original.reload.calculation_claimed_at
    end
    assert_equal 'no-referrer', response.headers['Referrer-Policy']
  end

  private

  def with_constant(owner, name, value)
    previous = owner.const_get(name)
    owner.send(:remove_const, name)
    owner.const_set(name, value)
    yield
  ensure
    owner.send(:remove_const, name)
    owner.const_set(name, previous)
  end

  def source
    User.create!(guest: true, email: "allocation_#{SecureRandom.hex(8)}@example.com", password: 'password123',
                 first_name: 'Guest', last_name: 'Traveler', nationality: countries(:India))
  end

  def select_nationality
    patch calculator_preferences_path(locale: :en), params: { nationality_code: 'IN', destination: 'trips' }
  end

  def trip
    { country_id: countries(:Germany).id, entry_date: '2027-10-01', exit_date: '2027-10-05' }
  end

  def visa
    { visa_type: 'S', no_entries: 0, start_date: '2027-01-01', end_date: '2027-12-31' }
  end
end
